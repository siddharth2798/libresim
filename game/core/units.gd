class_name Units
## SI <-> display unit conversions. Only instruments/UI should call these.

const FT := 0.3048
const NM := 1852.0
const KT := 1852.0 / 3600.0  # m/s per knot
const LB := 0.45359237
const INHG := 3386.389  # Pa per inHg
const HPA := 100.0
const FPM := FT / 60.0  # m/s per ft/min
const LBF := 4.4482216
const SLUG_FT3 := 515.378818  # kg/m^3 per slug/ft^3
const PSF := 47.880259  # Pa per lb/ft^2


static func m_to_ft(m: float) -> float: return m / FT
static func ft_to_m(ft: float) -> float: return ft * FT
static func mps_to_kt(v: float) -> float: return v / KT
static func kt_to_mps(kt: float) -> float: return kt * KT
static func mps_to_fpm(v: float) -> float: return v / FPM
static func pa_to_inhg(p: float) -> float: return p / INHG
static func pa_to_hpa(p: float) -> float: return p / HPA
static func k_to_c(k: float) -> float: return k - 273.15
static func c_to_k(c: float) -> float: return c + 273.15
