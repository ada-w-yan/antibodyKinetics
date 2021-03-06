% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/RcppExports.R
\name{model_trajectory_cpp}
\alias{model_trajectory_cpp}
\title{Model trajectory calc cpp}
\usage{
model_trajectory_cpp(pars, times, logSigma)
}
\arguments{
\item{pars}{the vector of model parameters}

\item{times}{the vector of time in days to solve over}
}
\value{
a vector of antibody titres
}
\description{
Calculates the ferret model trajectory for a single infection event.
Uses a Cpp implementation for speed. Need to obey order of parameters as in the
example
}
\examples{
pars <- c("mu"=8,"tp"=12,"dp"=0.5,"ts"=10,"m"=0.003,
          "sigma"=0.01, "beta"=0.02,"c"=4,"y0_mod"=0,
           "primed"=0,"mod"=1,
          "x"=0,"t_i"=10,"y0"=0,"eff_y0"=0)
times <- seq(0,100,by=10)
y <- model_trajectory_cpp(pars,times)
}
\seealso{
Other model.functions: \code{\link{model_func_groups}},
  \code{\link{model_func}}, \code{\link{model_trajectory}}
}

