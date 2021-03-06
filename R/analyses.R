#' Deviance
#'
#' Calculates deviance of a vector with a given likelihood function
#' @param x a vector of parameters used to solve the likelihood function
#' @param likelihood a likelihood function taking just a vector of parameters
#' @return a single deviance value
#' @export
calc_deviance  <- function(x, likelihood){
    return(-2*(likelihood(x)))
}

#' Posterior mean
#'
#' Calculates posterior mean of a given MCMC chain
#' @param chain the MCMC chain with a lnlike column
#' @return the posterior mean
#' @export
calc_post_mean <- function(chain){
    return(-2*mean(chain$lnlike))
}

#' Posterior variance
#'
#' Calculates posterior variance from a given MCMC chain
#' @param chain the MCMC chain with a lnlike column
#' @return the posterior variance
#' @export
calc_post_var <- function(chain){
    meanBar <- calc_post_mean(chain)
    tmp <- 0
    for(i in 1:nrow(chain)){
        tmp <- tmp + (-2*chain[i,"lnlike"] - meanBar)^2
    }
  varBar <- (1/(nrow(chain)-1)) * sum(tmp)
  return(varBar)
}

#' DIC
#'
#' Calculates DIC from a given MCMC chain
#' @param chain the MCMC chain with a lnlike column and all columns (number of columns will be used
#' @return a single DIC value
#' @export
calculate_DIC <- function(chain){
    DIC <- calc_post_mean(chain) + calc_post_var(chain)/2
    return(DIC)
}

#' BIC calculation
#' 
#' Given an MCMC chain, calculates the BIC
#' @param chain the MCMC chain to be tested
#' @param parTab the parameter table used for this chain
#' @param dat the data
#' @return a single BIC value
#' @export
calculate_BIC <- function(chain, parTab, dat){
    n <- nrow(dat)*ncol(dat)
    maxLik <- -2*max(chain$lnlike)
    B <- length(parTab[parTab$fixed==0,"values"])*log(n)
    return(maxLik + B)
}

#' @export
calc_dic_2 <- function(lik.fun,chain){
    D.bar <- -2*mean(chain$lnlike)
    theta.bar <- as.numeric(summary(as.mcmc(chain[,2:(ncol(chain)-1)]))$statistics[,"Mean"])
   # print(theta.bar)
    D.hat <- -2*lik.fun(theta.bar)
    pD <- D.bar - D.hat
    pV <- var(-2*chain$lnlike)/2
    list(DIC=pD+D.bar,IC=2*pD+D.bar,pD=pD,pV=pV,Dbar=D.bar,Dhat=D.hat)
}
