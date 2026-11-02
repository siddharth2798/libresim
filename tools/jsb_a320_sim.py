"""Headless JSBSim runner for the A320-200 CFM (FlightGear A320-family FDE incl. the real FBW / FADEC systems).

Reference oracle for tuning libresim's hand-written control laws and FDM tests (tools/23_a320_reference.py). Not used at
game run time. Root, patched FDE and property stubs: jsb_a320_root.py. Usage:

    sim = A320Sim(); sim.load()
    sim.init(alt_ft=10000, kcas=250, weight_kg=64000, flaps=0, gear_down=False)
    sim.set_controls(throttle=0.6, pitch=0.0)      # pitch/roll stick -1..1 (FG sign: pitch -1 = pull)
    sim.step(1200)                                  # 10 s
    sim.get("aero/alpha-deg")

Bridge (what FlightGear's Nasal would feed each step; done in _bridge): /position/altitude-ft, -agl-ft,
/velocities/airspeed-kt, groundspeed-kt, /instrumentation/airspeed-indicator/indicated-speed-kt, /orientation/{roll-rate-
degps,pitch-rate-degps,roll-deg,heading-deg}, /gear/gear[i]/{wow,position-norm}, /engines/engine[i]/{n1,n2,state},
/accelerations/pilot-g; plus the one-time switches in _SWITCHES and a refill of the tiny engine pipe tanks 5/6/7.
"""
import math

import jsbsim

import jsb_a320_root as root

DT = 1.0 / 120.0
LB = 0.45359237
FT = 0.3048
KT = 0.514444
LBF = 4.4482216
# one-time FlightGear-side switches (all other stubs keep their upstream default or 0)
_SWITCHES = {"/services/chocks/enable": 0, "/systems/acconfig/autoconfig-running": 0, "/it-fbw/law": 0, "/systems/fbw/sidestick/active[0]": 1,
             "/systems/fbw/sidestick/active[1]": 0, "/controls/flight/rudder-trim-active": 0}
# cockpit switches of a normal in-flight / after-start configuration (FG Nasal autostart would set them)
_POWER = {**{f"/controls/fctl/switches/{n}": 1 for n in ("elac1", "elac2", "sec1", "sec2", "sec3", "fac1", "fac2")},
          "/controls/electrical/switches/bat-1": 1, "/controls/electrical/switches/bat-2": 1,
          "/controls/electrical/switches/gen-1": 1, "/controls/electrical/switches/gen-2": 1,
          "/controls/electrical/switches/bus-tie": 1, "/controls/electrical/switches/galley": 1,
          "/controls/hydraulic/switches/green-edp": 1, "/controls/hydraulic/switches/yellow-edp": 1,
          "/systems/hydraulic/blue-qty-input": 6.5, "/systems/hydraulic/green-qty-input": 12.0,
          "/systems/hydraulic/yellow-qty-input": 10.0, "/controls/hydraulic/switches/blue-elec": 1, "/controls/hydraulic/switches/ptu": 1,
          "/controls/fuel/switches/pump-left-1": 1, "/controls/fuel/switches/pump-left-2": 1,
          "/controls/fuel/switches/pump-right-1": 1, "/controls/fuel/switches/pump-right-2": 1,
          "/controls/fuel/switches/pump-center-1": 1, "/controls/fuel/switches/pump-center-2": 1,
          "/controls/pneumatics/switches/bleed-1": 1, "/controls/pneumatics/switches/bleed-2": 1,
          "/controls/pneumatics/switches/pack-1": 1, "/controls/pneumatics/switches/pack-2": 1}
FLAP_LEVER = (0.0, 0.25, 0.5, 0.75, 1.0)   # 0, 1, 2, 3, FULL  (/controls/flight/flaps; detent 1 is 1+F below 100 kt rules)


class A320Sim:
    def __init__(self, rebuild=False, root_path=None):
        self.rebuild = rebuild
        self.root_path = root_path   # given: use this root as is (stub discovery probe), else root.ensure()
        self.f = None
        self.fuel_used_kg = 0.0
        self.t = 0.0
        self._nz_u = 0.0
        self._nz_e = 0.0
        self.holding = False

    def load(self):
        path = self.root_path or root.ensure(self.rebuild, verbose=False)
        self.f = jsbsim.FGFDMExec(str(path))
        self.f.set_debug_level(0)
        self.f.load_model(root.MODEL)
        return self

    # --- property access -------------------------------------------------------------------------------------------
    def get(self, name):
        return self.f[name]

    def set(self, name, v):
        self.f[name] = v

    def n_tanks(self):
        n = 0
        while self._has(f"propulsion/tank[{n}]/contents-lbs"):
            n += 1
        return n

    # --- setup -----------------------------------------------------------------------------------------------------
    def init(self, alt_ft=0.0, kcas=0.0, weight_kg=None, flaps=0, gear_down=True, gamma_deg=0.0, on_ground=False,
             mach=None, payload_kg=None, running=True, temp_dev_c=0.0, settle_s=15.0, ground_cg_ft=8.0):
        """Reset to an initial condition. weight_kg: total (fuel tuned; payload scaled down if fuel would be < 800 kg).
        settle_s: seconds to let electrics / hydraulics / FADEC / engines come up before returning: airborne the aircraft is
        pinned with forces/hold-down and run_ic() re-applies the IC afterwards (system state is kept); on the ground the
        parking brake is set. Do not call init twice on one sim: use a new A320Sim (system state carries over)."""
        f = self.f
        for k, v in {**_SWITCHES, **_POWER}.items():
            f[k] = v
        if weight_kg:
            self._set_weight(weight_kg, payload_kg)
        f["ic/h-sl-ft"] = alt_ft
        f["ic/terrain-elevation-ft"] = 0.0
        if on_ground:
            f["ic/h-agl-ft"] = ground_cg_ft   # CG height at rest on the gear (measured, see 23_a320_reference.py)
        if mach is not None:
            f["ic/mach"] = mach
        else:
            f["ic/vc-kts"] = kcas
        f["ic/gamma-deg"] = gamma_deg
        f["ic/psi-true-deg"] = 0.0
        f["atmosphere/delta-T"] = temp_dev_c * 1.8
        f["/controls/gear/lever-cockpit"] = 2 if gear_down else 0
        f["/controls/flight/flaps"] = FLAP_LEVER[flaps]
        self._refill()
        self._bridge()
        f.run_ic()
        self._bridge()
        if running:
            f["propulsion/set-running"] = -1
            for i in (0, 1):
                f[f"/engines/engine[{i}]/state"] = 3
        if settle_s:
            self._settle(settle_s, on_ground, alt_ft, kcas, mach)
        self.t = 0.0
        self.fuel_used_kg = 0.0
        return self

    def _settle(self, seconds, on_ground, alt_ft, kcas, mach):
        f = self.f
        f["/controls/gear/brake-parking"] = 1
        f["forces/hold-down"] = 1
        self.holding = True            # pinned: no load factor is flowing
        self.step(int(seconds / DT))
        self.holding = False
        f["forces/hold-down"] = 0
        f["/controls/gear/brake-parking"] = 0
        f.run_ic()
        self._bridge()

    def _set_weight(self, weight_kg, payload_kg):
        f = self.f
        empty = f["inertia/empty-weight-lbs"]
        pm = [f[f"inertia/pointmass-weight-lbs[{i}]"] for i in range(self._n_pm())]
        pay = sum(pm)
        want = weight_kg / LB - empty
        fuel_lb = want - (pay if payload_kg is None else payload_kg / LB)
        if fuel_lb < 800 / LB:
            fuel_lb = 800 / LB
            scale = max(0.0, (want - fuel_lb) / pay)
            for i, w in enumerate(pm):
                f[f"inertia/pointmass-weight-lbs[{i}]"] = w * scale
        elif payload_kg is not None:
            for i, w in enumerate(pm):
                f[f"inertia/pointmass-weight-lbs[{i}]"] = w * (payload_kg / LB) / pay
        # tanks 0..4 = L outer, L inner, centre, R inner, R outer (5..7 are the engine / APU pipe tanks)
        caps = {}
        for i in range(5):
            pct = f[f"propulsion/tank[{i}]/pct-full"]
            caps[i] = f[f"propulsion/tank[{i}]/contents-lbs"] / pct * 100.0 if pct > 0 else 0.0
        wing = (0, 1, 3, 4)
        wing_cap = sum(caps[i] for i in wing)
        in_wing = min(fuel_lb, wing_cap)
        for i in wing:
            f[f"propulsion/tank[{i}]/contents-lbs"] = in_wing * caps[i] / wing_cap
        f["propulsion/tank[2]/contents-lbs"] = max(0.0, fuel_lb - in_wing)
        self._fuel_tanks = (1, 3)

    # --- stepping --------------------------------------------------------------------------------------------------
    def _refill(self):
        for i in (5, 6, 7):
            self.f[f"propulsion/tank[{i}]/contents-lbs"] = 20.0

    def _bridge(self):
        f = self.f
        f["/sim/time/elapsed-sec"] = 100.0 + self.t
        f["/position/altitude-agl-ft"] = f["position/h-agl-ft"]
        f["/position/altitude-ft"] = f["position/h-sl-ft"]
        f["/velocities/airspeed-kt"] = f["velocities/vc-kts"]
        f["/instrumentation/airspeed-indicator/indicated-speed-kt"] = f["velocities/vc-kts"]
        f["/velocities/groundspeed-kt"] = f["velocities/vg-fps"] * 0.592484
        f["/orientation/roll-rate-degps"] = math.degrees(f["velocities/p-rad_sec"])
        f["/orientation/pitch-rate-degps"] = math.degrees(f["velocities/q-rad_sec"])
        f["/orientation/roll-deg"] = f["attitude/phi-deg"]
        f["/orientation/heading-deg"] = f["attitude/psi-deg"]
        for i in range(3):
            f[f"/gear/gear[{i}]/wow"] = f[f"gear/unit[{i}]/WOW"]
            f[f"/gear/gear[{i}]/position-norm"] = f[f"gear/unit[{i}]/pos-norm"]
        for i in (0, 1):
            f[f"/engines/engine[{i}]/n1"] = f[f"propulsion/engine[{i}]/n1"]
            f[f"/engines/engine[{i}]/n2"] = f[f"propulsion/engine[{i}]/n2"]
        f["/accelerations/pilot-g"] = f["accelerations/Nz"]
        self._load_factor_pi()

    def _load_factor_pi(self):
        """FlightGear runs Systems/a320-fbw-rules.xml next to JSBSim: a pi-simple-controller from
        /systems/fbw/pitch/load-factor-error (reference 0) to /systems/fbw/pitch/load-factor-pi. Re-implemented here in
        velocity form  u += Ki*dt*e + Kp*(e - e_prev), e = reference - input, with the file's gains (Kp -1.0 @140 kt .. -0.5 @350 kt,
        Ki -1.2 .. -0.7 only airborne in law 0/1, else 0) and output limits (between 0 and /systems/fbw/pitch/e-i-sum).
        FG's exact update order / rate is not reproduced (we run it at 120 Hz)."""
        f = self.f
        if self.holding:   # pinned by forces/hold-down during the settle: no load factor flows, keep the controller at rest
            self._nz_u = self._nz_e = 0.0
            f["/systems/fbw/pitch/load-factor-pi"] = 0.0
            return
        vc = f["velocities/vc-kts"]
        k = max(0.0, min(1.0, (vc - 140.0) / 210.0))
        kp = -1.0 + 0.5 * k
        law_ok = f["/it-fbw/law"] in (0, 1)
        ki = (-1.2 + 0.5 * k) if (not f["position/wow"] and law_ok) else 0.0
        e = -f["/systems/fbw/pitch/load-factor-error"]
        cmd = f["/systems/fbw/pitch/e-i-sum"]
        lo, hi = (cmd, 0.0) if cmd < 0 else (0.0, cmd)
        self._nz_u += ki * DT * e + kp * (e - self._nz_e)
        self._nz_e = e
        self._nz_u = max(lo, min(hi, self._nz_u))
        f["/systems/fbw/pitch/load-factor-pi"] = self._nz_u

    def set_controls(self, throttle=None, pitch=None, roll=None, rudder=None, flaps=None, gear_down=None,
                     brake=None, parking_brake=None, speedbrake=None, trim=None, engines=(0, 1), steer_tiller=None):
        """throttle: lever 0..1 (idle 0, CL 0.625, MCT 0.8, TOGA 1.0), per engine in `engines`. pitch/roll/rudder -1..1
        (FG sign: pitch -1 pulls). flaps: lever index 0..4. trim: /controls/flight/elevator-trim (THS norm)."""
        f = self.f
        if throttle is not None:
            for i in engines:
                f[f"/controls/engines/engine[{i}]/throttle"] = throttle
        for name, v in (("elevator[0]", pitch), ("aileron[0]", roll), ("rudder[0]", rudder), ("speedbrake", speedbrake),
                        ("elevator-trim", trim)):
            if v is not None:
                f[f"/controls/flight/{name}"] = v
        if flaps is not None:
            f["/controls/flight/flaps"] = FLAP_LEVER[flaps]
        if gear_down is not None:
            f["/controls/gear/lever-cockpit"] = 2 if gear_down else 0
        if brake is not None:
            f["/controls/gear/brake-left"] = f["/controls/gear/brake-right"] = brake
        if parking_brake is not None:
            f["/controls/gear/brake-parking"] = parking_brake

    def step(self, n=1):
        f = self.f
        for _ in range(n):
            self._bridge()
            self._refill()
            f.run()
            used = 0.0
            for i in (0, 1):
                used += f[f"propulsion/engine[{i}]/fuel-flow-rate-pps"] * DT
            self.fuel_used_kg += used * LB
            if used and getattr(self, "_fuel_tanks", None):
                for i in self._fuel_tanks:
                    k = f"propulsion/tank[{i}]/contents-lbs"
                    f[k] = max(0.0, f[k] - used / len(self._fuel_tanks))
            self.t += DT

    # --- derived readouts ------------------------------------------------------------------------------------------
    def snapshot(self):
        f = self.f
        return {
            "t": self.t, "alt_ft": f["position/h-sl-ft"], "kcas": f["velocities/vc-kts"], "mach": f["velocities/mach"],
            "ktas": f["velocities/vt-fps"] / 1.687810, "gs_kt": f["velocities/vg-fps"] * 0.592484,
            "alpha_deg": f["aero/alpha-deg"], "pitch_deg": f["attitude/theta-deg"], "roll_deg": f["attitude/phi-deg"],
            "gamma_deg": f["flight-path/gamma-deg"], "vs_fpm": f["velocities/h-dot-fps"] * 60,
            "nz": f["accelerations/Nz"], "q_dps": math.degrees(f["velocities/q-rad_sec"]),
            "p_dps": math.degrees(f["velocities/p-rad_sec"]), "r_dps": math.degrees(f["velocities/r-rad_sec"]),
            "n1_1": f["propulsion/engine[0]/n1"], "n1_2": f["propulsion/engine[1]/n1"],
            "thrust_n_1": f["propulsion/engine[0]/thrust-lbs"] * LBF, "thrust_n_2": f["propulsion/engine[1]/thrust-lbs"] * LBF,
            "ff_kgh_1": f["propulsion/engine[0]/fuel-flow-rate-pps"] * LB * 3600,
            "ff_kgh_2": f["propulsion/engine[1]/fuel-flow-rate-pps"] * LB * 3600,
            "elev_l_deg": f["/systems/fcs/elevator-l/final-deg"] if self._has("/systems/fcs/elevator-l/final-deg") else None,
            "ths_deg": f["/systems/fcs/stabilizer/final-deg"] if self._has("/systems/fcs/stabilizer/final-deg") else None,
            "flap_deg": f["fcs/flap-pos-deg"], "slat_deg": f["fcs/slat-pos-deg"], "weight_kg": f["inertia/weight-lbs"] * LB,
            "wow": f["gear/unit[1]/WOW"], "dist_m": f["position/distance-from-start-mag-mt"],
        }

    def _n_pm(self):
        n = 0
        while self._has(f"inertia/pointmass-weight-lbs[{n}]"):
            n += 1
        return n

    def _has(self, name):
        try:
            self.f[name]
            return True
        except Exception:
            return False
