const MAX_INIT_RESIDUAL = 10.0
const BOUNDS_TOLERANCE = 1e-6
const MAX_REACTIVE_POWER_ITERATIONS = 10
const DEFAULT_MAX_REDISTRIBUTION_ITERATIONS = 10
const LARGE_RESIDUAL = 10 # threshold for "bad initial guess": default
# norm(residual, 1)/length(residual) > 10.

const ISAPPROX_ZERO_TOLERANCE = 1e-6

const DEFAULT_NR_MAX_ITER::Int64 = 30   # default maxIterations for the NR power flow
const DEFAULT_NR_TOL::Float64 = 1e-9 # default tolerance for the NR power flow
const DEFAULT_REFINEMENT_THRESHOLD = 5e-2 # do refinement if relative error > 5%.
const DEFAULT_REFINEMENT_MAX_ITER = 10 # how many times to try iterative refinement
const DEFAULT_REFINEMENT_EPS::Float64 = 1e-6 # when to stop iterative refinement.
const NR_SINGULAR_SCALING = 1e-6 # scaling factor in fallback method for singular Jacobian
# only used for trust region.
const DEFAULT_TRUST_REGION_ETA::Float64 = 1e-4 # if actual improvement/predicted improvement
# is < eta, then reject the step Δx, shrink the trust region, and try again.
const DEFAULT_TRUST_REGION_FACTOR::Float64 = 1.0 # controls starting size of trust region
# improvement factor cutoffs for updating size of trust region.
const HALVE_TRUST_REGION = 0.1
const MAX_DOUBLE_TRUST_REGION = 0.5
const DOUBLE_TRUST_REGION = 0.9

const AC_PF_KW = []

const PSSE_DEFAULT_EXPORT_NAME = "export"

const BUS_VOLTAGE_MAGNITUDE_CUTOFF_MIN = 0.8
const BUS_VOLTAGE_MAGNITUDE_CUTOFF_MAX = 1.2

const TIs = Union{Int32, Int64}
