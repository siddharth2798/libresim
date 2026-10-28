import jsbsim, sys, math
exec(open("spike6.py").read().split("f[\"ic/h-sl-ft\"]")[0].replace("f=jsbsim.FGFDMExec(sys.argv[1]); f.set_debug_level(0)\nf.load_model(\"A320-200-CFM\")","f=jsbsim.FGFDMExec(sys.argv[1]); f.set_debug_level(0); f.load_model('A320-200-CFM')"))
f["ic/h-sl-ft"]=10000; f["ic/vc-kts"]=250; f["ic/gamma-deg"]=0
f["/systems/acconfig/autoconfig-running"]=1
f.run_ic()
bridge()
f.run_ic()
bridge()
f["propulsion/set-running"]=-1

names=["/systems/fadec/limit/idle-norm","/systems/fadec/limit/idle","/systems/fadec/limit/idle-table","/systems/fadec/control-1/lever-norm","/systems/fadec/control-1/throttle-output","/systems/fadec/control-1/throttle-pos","/systems/fadec/control-1/throttle-lag","/systems/fadec/control-1/throttle-fdm","/systems/fadec/limit/toga-norm","/systems/fadec/thr-locked-norm","/systems/fadec/athr/output","/systems/fadec/reverse-1/throttle-rev","propulsion/tat-c","/position/altitude-ft","/systems/fadec/limit/active-n1","/systems/fadec/control-1/lever-n1","/systems/fadec/limit/idle"]
for t in range(2):
    bridge(); f.run()
    print(t,[(n.split("/")[-1],f[n]) for n in names])
