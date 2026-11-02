import jsbsim, sys, math
f=jsbsim.FGFDMExec(sys.argv[1]); f.set_debug_level(0)
f.load_model("A320-200-CFM")
G=lambda k: f[k]
def bridge():
    f["/position/altitude-agl-ft"]=f["position/h-agl-ft"]; f["/position/altitude-ft"]=f["position/h-sl-ft"]
    f["/velocities/airspeed-kt"]=f["velocities/vc-kts"]; f["/instrumentation/airspeed-indicator/indicated-speed-kt"]=f["velocities/vc-kts"]
    f["/velocities/groundspeed-kt"]=f["velocities/vg-fps"]*0.592484
    f["/orientation/roll-rate-degps"]=math.degrees(f["velocities/p-rad_sec"]); f["/orientation/pitch-rate-degps"]=math.degrees(f["velocities/q-rad_sec"])
    f["/orientation/roll-deg"]=f["attitude/phi-deg"]; f["/orientation/heading-deg"]=f["attitude/psi-deg"]
    for i in range(3):
        f[f"/gear/gear[{i}]/wow"]=f[f"gear/unit[{i}]/WOW"]; f[f"/gear/gear[{i}]/position-norm"]=f[f"gear/unit[{i}]/pos-norm"]
    for i in range(2):
        f[f"/engines/engine[{i}]/n1"]=f[f"propulsion/engine[{i}]/n1"]; f[f"/engines/engine[{i}]/n2"]=f[f"propulsion/engine[{i}]/n2"]
    f["/accelerations/pilot-g"]=-f["accelerations/Nz"]
f["ic/h-sl-ft"]=10000; f["ic/vc-kts"]=250; f["ic/gamma-deg"]=0; f["ic/psi-true-deg"]=0
f["/systems/acconfig/autoconfig-running"]=1
f.run_ic()
f["propulsion/set-running"]=-1
f["/controls/gear/lever-cockpit"]=0
for t in range(2400):
    bridge(); f["/controls/engines/engine[0]/throttle"]=0.6; f["/controls/engines/engine[1]/throttle"]=0.6
    f.run()
    if t%300==0:
        print(f"t={t/120:5.1f} h={f['position/h-sl-ft']:7.0f} vc={f['velocities/vc-kts']:6.1f} n1={f['propulsion/engine[0]/n1']:5.1f} thr={f['propulsion/engine[0]/thrust-lbs']:7.0f} alpha={f['aero/alpha-deg']:5.2f} elev={f['/systems/fcs/elevator-l/final-deg']:5.2f} ths={f['/systems/fcs/stabilizer/final-deg']:5.2f} gam={f['flight-path/gamma-deg']:5.2f} fuel={f['propulsion/total-fuel-lbs']:.0f} ff={f['propulsion/engine[0]/fuel-flow-rate-pps']:.2f} flap={f['fcs/flap-pos-deg']} mass={f['inertia/weight-lbs']:.0f}")
