% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/plots.R
\name{get_best_pars}
\alias{get_best_pars}
\title{Find best MCMC chain parameters}
\usage{
get_best_pars(chain)
}
\arguments{
\item{chain}{the MCMC chain}
}
\value{
a named vector of parameters
}
\description{
Given an MCMC chain, finds the row with the highest log likelihood. There must be a column named "lnlike"
which is the log likelihood. Will return the vector of all parameters other than "sampno","lnlike" and "strain"
}

