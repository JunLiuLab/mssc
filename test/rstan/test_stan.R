## options(mc.cores = parallel::detectCores()).
## rstan_options(auto_write = TRUE)

library(rstan)

schools_dat <- list(J = 8,
                    y = c(28,  8, -3,  7, -1,  1, 18, 12),
                    sigma = c(15, 10, 16, 11,  9, 11, 10, 18))
