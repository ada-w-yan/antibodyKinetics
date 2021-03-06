% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/model.R
\name{model_trajectory}
\alias{model_trajectory}
\title{Model trajectory calc}
\usage{
model_trajectory(pars, times, logSigma = TRUE)
}
\arguments{
\item{pars}{the named vector of model parameters}

\item{times}{the vector of time in days to solve over}

\item{logSigma}{if TRUE, uses the exponential of pars["sigma"]}
}
\value{
a vector of antibody titres
}
\description{
Calculates the ferret model trajectory for a single infection event.
Uses an R implementation so easy to code and has named parameter vectors.
}
\examples{
pars <- c("mu"=8,"dp"=0.5,"tp"=12,"ts"=10,"m"=0.003,"y0"=0,"t_i"=10,
          "sigma"=0.01, "beta"=0.02,"c"=4,"x"=0,"primed"=0,"mod"=1)
times <- seq(0,100,by=10)
y <- model_trajectory(pars,times,FALSE)
}
\seealso{
Other model.functions: \code{\link{model_func_groups}},
  \code{\link{model_func}},
  \code{\link{model_trajectory_cpp}}
}

