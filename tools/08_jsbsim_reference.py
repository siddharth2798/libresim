"""Reference numbers from standalone JSBSim (c172p) for the FDM test cards.
Usage: 08_jsbsim_reference.py   (prints climb rate at Vy and static RPM)
Uses data/raw/jsbsim/src as the JSBSim root.
"""
import jsbsim

import common as c

ROOT = str(c.RAW / "jsbsim" / "src")


def make(engine_hp=None):
    f = jsbsim.FGFDMExec(ROOT)
    f.set_debug_level(0)
    f.load_model("c172p")
    return f


def climb(gross_lb=2400.0, kias=74.0, alt_ft=1000.0):
    f = make()
    f["ic/h-sl-ft"] = alt_ft
    f["ic/vc-kts"] = kias
    f["ic/gamma-deg"] = 4.0
    f["ic/psi-true-deg"] = 0
    extra = gross_lb - 1878.0  # c172p default load; put the rest in the rear seats
    f["inertia/pointmass-weight-lbs[2]"] = extra / 2
    f["inertia/pointmass-weight-lbs[3]"] = extra / 2
    f.run_ic()
    f["propulsion/set-running"] = -1
    f["fcs/throttle-cmd-norm"] = 1.0
    f["fcs/mixture-cmd-norm"] = 1.0
    f["fcs/pitch-trim-cmd-norm"] = 0.0
    dt = f.get_delta_t()
    i_err = 0.0
    hist = []
    t = 0.0
    while t < 100.0:
        err = f["velocities/vc-kts"] - kias
        i_err += err * dt
        f["fcs/elevator-cmd-norm"] = max(-1, min(1, -(0.06 * err + 0.01 * i_err) - 0.1))
        f["fcs/aileron-cmd-norm"] = max(-1, min(1, -2.0 * f["attitude/phi-rad"] - 0.3 * f["velocities/p-rad_sec"]))
        f.run()
        t += dt
        if t > 40.0:
            hist.append((t, f["position/h-sl-ft"]))
    roc = (hist[-1][1] - hist[0][1]) / (hist[-1][0] - hist[0][0]) * 60.0
    print(f"JSBSim c172p climb at {f['velocities/vc-kts']:.0f} KCAS: {roc:.0f} fpm, "
          f"{f['propulsion/engine/engine-rpm']:.0f} RPM, weight {f['inertia/weight-lbs']:.0f} lb\n"
          f"   power {f['propulsion/engine/power-hp']:.0f} hp, thrust {f['propulsion/engine/thrust-lbs'] * 4.448:.0f} N, "
          f"drag {f['aero/coefficient/CDo'] + f['aero/coefficient/CDDf'] + f['aero/coefficient/CDwbh'] + f['aero/coefficient/CDDe'] + f['aero/coefficient/CDbeta']:.0f} lbf "
          f"({(f['aero/coefficient/CDo'] + f['aero/coefficient/CDDf'] + f['aero/coefficient/CDwbh'] + f['aero/coefficient/CDDe'] + f['aero/coefficient/CDbeta']) * 4.448:.0f} N), "
          f"alpha {f['aero/alpha-deg']:.1f} deg, elevator {f['fcs/elevator-pos-rad']:.3f} rad, J {f['propulsion/engine/advance-ratio']:.3f}")


if __name__ == "__main__":
    climb(1878.0)
    climb(2400.0)
