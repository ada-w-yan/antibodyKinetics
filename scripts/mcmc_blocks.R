#' Adaptive Metropolis-within-Gibbs Random Walk Algorithm.
#'
#' The Adaptive Metropolis-within-Gibbs algorithm. Given a starting point and the necessary MCMC parameters as set out below, performs a random-walk of the posterior space to produce an MCMC chain that can be used to generate MCMC density and iteration plots. The algorithm undergoes an adaptive period, where it changes the step size of the random walk for each parameter to approach the desired acceptance rate, popt. After this, a burn in period is established, and the algorithm then uses \code{\link{univ_proposal}} or \code{\link{mvr_proposal}} to explore the parameter space, recording the value and posterior value at each step. The MCMC chain is saved in blocks as a .csv file at the location given by filename.
#' @param parTab the parameter table controlling information such as bounds, initial values etc
#' @param data the data frame of data to be fitted
#' @param mcmcPars named vector named vector with parameters for the MCMC procedure. Iterations, popt, opt_freq, thin, burnin, adaptive_period and save_block.
#' @param filename the full filepath at which the MCMC chain should be saved. "_chain.csv" will be appended to the end of this, so filename should have no file extensions
#' @param CREATE_POSTERIOR_FUNC pointer to posterior function used to calculate a likelihood
#' @param mvrPars a list of parameters if using a multivariate proposal. Must contain an initial covariance matrix, weighting for adapting cov matrix, and an initial scaling parameter (0-1)
#' @param PRIOR_FUNC user function of prior for model parameters. Should take values, names and local from param_table
#' @return a list with: 1) full file path at which the MCMC chain is saved as a .csv file; 2) the last used covarianec matrix; 3) the last used scale size
#' @export
#' @useDynLib antibodyKinetics
run_MCMC_blocks<- function(parTab,
                     data=NULL,
                     mcmcPars,
                     filename,
                     CREATE_POSTERIOR_FUNC=NULL,
                     mvrPars=NULL,
                     PRIOR_FUNC=NULL){
    ## Allowable error in scale tuning
    TUNING_ERROR <- 0.1
    OPT_TUNING  <- 0.2
    
    ## Extract MCMC parameters
    iterations <- mcmcPars["iterations"]
    popt <- mcmcPars["popt"]
    opt_freq<- mcmcPars["opt_freq"]
    thin <- mcmcPars["thin"]
    adaptive_period<- mcmcPars["adaptive_period"]
    save_block <- mcmcPars["save_block"]

    param_length <- nrow(parTab)
    unfixed_pars <- which(parTab$fixed == 0)
    unfixed_par_length <- nrow(parTab[parTab$fixed== 0,])
    current_pars <- parTab$values
    par_names <- parTab$names

    ## Parameter constraints
    lower_bounds <- parTab$lower_bounds
    upper_bounds <- parTab$upper_bounds
    steps <- parTab$steps
    fixed <- parTab$fixed
    
    ## Arrays to store acceptance rates
    ## If univariate proposals
    if(is.null(mvrPars)){
        tempaccepted <- tempiter <- integer(param_length)
        reset <- integer(param_length)
        reset[] <- 0
    } else { # If multivariate proposals
        #tempaccepted <- tempiter <- 0
        covMat <- mvrPars[[1]][unfixed_pars,unfixed_pars]
        w <- mvrPars[[3]]

        ## Might be doing block updating
        blocks <- unique(parTab$block)
        block_indices <- parTab$block
        unfixed_block_indices <- parTab[parTab$fixed == 0, "block"]
        print(blocks)
        scales <- rep(mvrPars[[2]],length(blocks))
        reset <- tempaccepted <- tempiter <- integer(length(blocks))
        reset[] <- 0
        
    }
    posterior_simp <- protect(CREATE_POSTERIOR_FUNC(parTab,data, PRIOR_FUNC))

    ## Setup MCMC chain file with correct column names
    mcmc_chain_file <- paste(filename,"_chain.csv",sep="")
    chain_colnames <- c("sampno",par_names,"lnlike")

    ## Create empty chain to store every iteration for the adaptive period
    opt_chain <- matrix(nrow=adaptive_period,ncol=unfixed_par_length)
    chain_index <- 1
    
    ## Create empty chain to store "save_block" iterations at a time
    save_chain <- empty_save_chain <- matrix(nrow=save_block,ncol=param_length+2)

    ## Initial conditions ------------------------------------------------------
    ## Initial likelihood
    probab <- posterior_simp(current_pars)

    ## Set up initial csv file
    tmp_table <- array(dim=c(1,length(chain_colnames)))
    tmp_table <- as.data.frame(tmp_table)
  
    tmp_table[1,] <- c(1,current_pars,probab)
    colnames(tmp_table) <- chain_colnames
    
    ## Write starting conditions to file
    write.table(tmp_table,file=mcmc_chain_file,row.names=FALSE,col.names=TRUE,sep=",",append=FALSE)

    ## Initial indexing parameters
    no_recorded <- 1
    sampno <- 2
    par_i <- 1
    
    for (i in 1:(iterations+adaptive_period)){
        ## If using univariate proposals
        if(is.null(mvrPars)) {
            ## For each parameter (Gibbs)
            j <- unfixed_pars[par_i]
            par_i <- par_i + 1
            if(par_i > unfixed_par_length) par_i <- 1
            proposal <- univ_proposal(current_pars, lower_bounds, upper_bounds, steps,j)
            
            tempiter[j] <- tempiter[j] + 1
            ## If using multivariate proposals
        } else {
            j <- blocks[par_i]
            #message(cat("Block: ",j))
            indices <- intersect(which(block_indices == j), unfixed_pars)
            indices1 <- which(unfixed_block_indices == j)
           #message(cat("Indices: ", indices))
            #message(cat("Scale: ",scales[par_i]))
            proposal <- mvr_proposal(current_pars, indices, scales[par_i]*covMat[indices1,indices1])
            tempiter[par_i] <- tempiter[par_i] + 1
            par_i <- par_i + 1
            if(par_i > length(blocks)) par_i <- 1
        }
        ## Propose new parameters and calculate posterior
        ## Check that all proposed parameters are in allowable range
        if(!any(
                proposal[unfixed_pars] < lower_bounds[unfixed_pars] |
                proposal[unfixed_pars] > upper_bounds[unfixed_pars]
            )
           ){
            ## Calculate new likelihood and find difference to old likelihood
            new_probab <- posterior_simp(proposal)

            log_prob <- min(new_probab-probab,0)
         
            ## Accept with probability 1 if better, or proportional to
            ## difference if not
            if(is.finite(log_prob) && log(runif(1)) < log_prob){
                current_pars <- proposal
                probab <- new_probab
                
                ## Store acceptances
                if(is.null(mvrPars)){
                    tempaccepted[j] <- tempaccepted[j] + 1
                } else {
                    #message(cat("par_i: ", par_i))
                    tempaccepted[par_i]<- tempaccepted[par_i] + 1
                }
            }
        }
        
        
        ## If current iteration matches with recording frequency, store in the chain. If we are at the limit of the save block,
        ## save this block of chain to file and reset chain
        if(i %% thin ==0){
            save_chain[no_recorded,1] <- sampno
            save_chain[no_recorded,2:(ncol(save_chain)-1)] <- current_pars
            save_chain[no_recorded,ncol(save_chain)] <- probab
            no_recorded <- no_recorded + 1
        }

       
        
        ## If within adaptive period, need to do some adapting!
        if(i <= adaptive_period){
            ## Current acceptance rate
            pcur <- tempaccepted/tempiter
            ## Save each step
            opt_chain[chain_index,] <- current_pars[unfixed_pars]
           
            ## If in an adaptive step
            if(chain_index %% opt_freq == 0){
                ## If using univariate proposals
                if(is.null(mvrPars)){
                    ## For each non fixed parameter, scale the step size
                    for(x in unfixed_pars) steps[x] <- scaletuning(steps[x],popt,pcur[x])
                    message(cat("Pcur: ", pcur[unfixed_pars],sep="\t"))
                    message(cat("Step sizes: ", steps[unfixed_pars],sep="\t"))
                    tempaccepted <- tempiter <- reset

                } else {       ## If using multivariate proposals
                    if(chain_index > OPT_TUNING*adaptive_period & chain_index < (0.8*adaptive_period)){
                        oldCovMat <- covMat
                        ##if(pcur == 0){
                        ##    message("Using old covMat")
                        ##    covMat <- oldCovMat
                        ##} else {
                        #indices <- intersect(which(block_indices == 2), unfixed_pars)
                        indices1 <- which(unfixed_block_indices == 2)
                        covMat[indices1,indices1] <- cov(opt_chain[1:chain_index,indices1])
                        #covMat <- cov(opt_chain[1:chain_index,])
                        ##}
                        covMat[indices1,indices1] <- w*covMat[indices1,indices1] + (1-w)*oldCovMat[indices1,indices1]
                        #covMat[indices1,indices1] <- w*covMat[indices1,indices1] + (1-w)*oldCovMat[indices1,indices1]
                    }
                    if(chain_index > (0.8)*adaptive_period){
                        for(x in 1:length(scales)){
                            if(pcur[x] > (popt + TUNING_ERROR*popt) | pcur[x] < (popt - TUNING_ERROR*popt)){
                                scales[x] <- scaletuning(scales[x], popt,pcur[x])
                            }
                            message(cat("Cur scale: ", scales[x]))
                            message(cat("Pcur: ", pcur[x]))
                        }                        
                    }
                    ##message(cat("Temp iter: ", tempiter,sep="\t"))
                    ##message(cat("Temp accepted: ", tempaccepted,sep="\t"))
                    tempiter <- tempaccepted <- reset
                    ## message(cat("Optimisation iteration: ", i,sep="\t"))
                    ## Print acceptance rate

                    message(cat("Pcur: ", pcur,sep="\t"))
                    message(cat("Scale: ", scales,sep="\t"))
                }
            }
            chain_index <- chain_index + 1
        }
        if(i %% save_block == 0){
            message(cat("Current iteration: ", i, sep="\t"))
            ## Print out optimisation frequencies
        }
        
        if(no_recorded == save_block){
            write.table(save_chain[1:(no_recorded-1),],file=mcmc_chain_file,col.names=FALSE,row.names=FALSE,sep=",",append=TRUE)
            save_chain <- empty_save_chain
            no_recorded <- 1
        }
        sampno <- sampno + 1
    }
    
    ## If there are some recorded values left that haven't been saved, then append these to the MCMC chain file. Note
    ## that due to the use of cbind, we have to check to make sure that (no_recorded-1) would not result in a single value
    ## rather than an array
    if(no_recorded > 2){
        write.table(save_chain[1:(no_recorded-1),],file=mcmc_chain_file,row.names=FALSE,col.names=FALSE,sep=",",append=TRUE)
    }

    if(is.null(mvrPars)){
        covMat <- NULL
        scale <- NULL
    } else {
        steps <- NULL
    }
    return(list("file"=mcmc_chain_file,"covMat"=covMat,"scale"=scale, "steps"=steps))
}

