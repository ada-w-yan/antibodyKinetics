#' Antigenic distance calc
#'
#' Calculates the necessary antigenic distance needed to give a given
#' percentage cross reactivity with gradient m and percentage y
#' @param y the desired proportion cross reactivity
#' @param m the rate of the exponential function for cross reactivity
#' @return a single value, x#'
#' @export
#' @useDynLib antibodyKinetics
calculate_x <- function(y, m){
  return(-log(y)/m)
}

#' Model trajectory calc
#'
#' Calculates the ferret model trajectory for a single infection event.
#' Uses an R implementation so easy to code and has named parameter vectors.
#' @param pars the named vector of model parameters
#' @param times the vector of time in days to solve over
#' @param logSigma if TRUE, uses the exponential of pars["sigma"]
#' @return a vector of antibody titres
#' @export
#' @family model functions
#' @useDynLib antibodyKinetics
#' @examples
#' pars <- c("mu"=8,"dp"=0.5,"tp"=12,"ts"=10,"m"=0.003,"y0"=0,"t_i"=10,
#'           "sigma"=0.01, "beta"=0.02,"c"=4,"x"=0,"primed"=0,"mod"=1)
#' times <- seq(0,100,by=10)
#' y <- model_trajectory(pars,times,FALSE)
model_trajectory <- function(pars, times, logSigma=TRUE){
    ## Calculate modified mu from cross reactivity and modifiers
    mu <- pars["mu"]
    dp <- pars["dp"]
    tp <- pars["tp"]
    ts <- pars["ts"]
    m <- pars["m"]
    y0 <- pars["y0"]
    eff_y0 <- pars["eff_y0"]
    t_i <- pars["t_i"]
    lower_bound <- pars["lower_bound"]

    if(logSigma){
        sigma <- exp(pars["sigma"])
        beta <- exp(pars["beta"])
        y0_mod <- exp(pars["y0_mod"])
    } else {
        sigma <-  pars["sigma"]
        beta <- pars["beta"]
        y0_mod <- pars["y0_mod"]
    }

    ## mu = f(y0)
    mu <- mu*exp(-max(y0,0)*y0_mod)
    cr <- exp(-sigma*pars["x"])
    prime_cr <- pars["c"]*exp(-beta*pars["x"])*pars["primed"]
    print(pars["x"])
    mu <- mu*cr*pars["mod"] + prime_cr
    #print(paste0("CR: ",cr))
    y <- numeric(length(times))
    i <- 1
    ## Loops through all times and calculate titre based on time relative to time of infection
    for(t in times){
        tmp <- 0
        if(t <= t_i) tmp = 0
        else if(t > t_i & t <= (t_i + tp)) tmp = (mu/tp)*(t-t_i)
        else if(t > (tp+t_i) & t <=(ts + t_i+tp)) tmp = ((-(dp*mu)/ts)*(t) + ((mu*dp)/ts)*(t_i+tp) + mu)
        else tmp = (-m*(t)+m*(t_i+tp+ts)+(1-dp)*mu)
        y[i] <- tmp + eff_y0
        if(y[i] < lower_bound) y[i] = lower_bound
        i <- i + 1
    }
    return(y)
}

#' Multiple group model trajectory
#'
#' Calculates model trajectories for multiple groups
#' @param parTab the parameter table containing at least a values
#' column and a names column which can be used to solve \code{\link{model_trajectory}}
#' @param cr_table the cross reactivity part of the parameter table, with values and names for the exposure strain, the measured strain, and the antigenic distance (x)
#' @param order_tab the table for parameters modifying boosting based on infection order (antigenic seniority)
#' @param exposures the table for exposure types and times
#' @param strains a vector with the names of all of the strains involved in the model
#' @param times a vector of times to solve the model over
#' @param MODEL_FUNC pointer to the R function that will be used to solve the model. 
#' @return a table of antibody titres for the given times, with a column for times, group and colnames of the measured strain
#' @export
#' @useDynLib antibodyKinetics
#' @family model functions
#' @seealso \code{\link{model_func_isolated}} for next level, \code{link{model_trajectory}} for model solving code
model_func_groups <- function(parTab, cr_table, order_tab, exposures, strains, times, version=0,cross_reactivity=FALSE,typing=FALSE){
    ## Get unique groups (groups of exposures)
    groups <- unique(exposures$group)

    ## Precompute matrix to save antibody titres
    y <- matrix(nrow=length(times)*length(groups),ncol=length(strains))
    colnames(y) <- strains
    y <- data.frame(times=rep(times, length(groups)),y, group=rep(groups,each=length(times)))
    ## For each group, isolate group specific exposures and solve model
    for(group in groups){
        tmpExposures <- exposures[exposures$group == group,] 
        y[y$group==group,strains] <- model_func(parTab, cr_table, order_tab, tmpExposures, strains, times, version, cross_reactivity, typing)
    }
    return(y)
}

#' Model solver for one group, competitive process
#'
#' Solves the antibody kinetics model for a single group, which may have multiple measured and exposure strains. This particular implementation assumes that each subsequent exposure supercedes the previous one
#' @param parTab the parameter table containing at least a values
#' column and a names column which can be used to solve \code{\link{model_trajectory}}
#' @param cr_table the cross reactivity part of the parameter table, with values and names for the exposure strain, the measured strain, and the antigenic distance (x)
#' @param order_tab the table for parameters modifying boosting based on infection order (antigenic seniority)
#' @param exposures the table for exposure types and times
#' @param strains a vector with the names of all of the strains involved in the model
#' @param times a vector of times to solve the model over
#' @param version 0 for isolated, 1 for competitive
#' @return a table of antibody titres for the given times, with a column for times and colnames of the measured strain
#' @export
#' @useDynLib antibodyKinetics
#' @family model functions
model_func <- function(parTab, cr_table, order_tab, all_exposures, strains, times, version=0,cross_reactivity=FALSE,typing=FALSE){
    trajectories <- matrix(0, ncol=length(strains),nrow=length(times))
    index <- 1
    ## For each strain to be measured
    for(strain in strains){
        print(strain)
        y <- 0
        ## To avoid problems with having multiple exposures at the same time, we enumerate which
        ## exposures relate to a particular strain
        exposures <- all_exposures[all_exposures$strain == strain,]
        ## For each exposure
        for(i in 1:nrow(exposures)){
            tmpTimes <- times
            y0 <- y[length(y)]

            ## Get exposure time, type and exposure strain
            ## Also end time of trajectory to calculate
            t_i <- exposures[i,"values"]
            next_t <- exposures[i,"next_t"]
            type <- exposures[i,"type"]
            id <- exposures[i,"id"]
            exposure <- exposures[i,"exposure"]

            ## Is this first, second etc exposure?
            order <- exposures[i,"order"]

            ## Was there priming?
            isPrimed <- exposures[i,"primed"]

            ## Get model parameters for this type of exposure
            #######################################################################################
            ## VERSION SPECIFIC SUB SETS
            #######################################################################################
            ## If using exposure type-specific parameters, get parameters for this exposure type
            ## Otherwise, get the parameters for this particular exposure id
            if(typing){
              tmpParTab <- parTab[parTab$type %in% c(type,"all"),]
            } else {
              tmpParTab <- parTab[parTab$id %in% c("all",id),]
            }
            
            ## If not using cross reactivity, need to get strain-specific parameters
            if(cross_reactivity){
              ## Find the antigenic distance between the measured and exposure strain
              ## This will either by type specific or universal depending on what's in the parameter table
              ind <- sort(c(exposure,strain))
              x <- cr_table[cr_table$exposure==ind[1] & cr_table$strain == ind[2],"values"]
            } else {
              tmpParTab <- tmpParTab[tmpParTab$strain %in% c(strain, "all", NA),]
              x <- 0
            }
            pars <- tmpParTab$values
            names(pars) <- tmpParTab$names

            ## Get the correct modifier for this exposure order
            mod <- order_tab[order_tab$order == order,"values"]

            if(version == 1){
              tmpTimesI <- which(times >= t_i & times < next_t)
              eff_y0 <- y0
              if(i == nrow(exposures)){
                tmpTimesI <- which(times >= t_i & times <= next_t)
              }
            } else {
              tmpTimesI <- seq_along(times)
              eff_y0 <- 0
            }
            tmpTimes <- times[tmpTimesI]
            tmpTimes <- c(tmpTimes, next_t)
              
            ## Solve model
            pars <- c("t_i"=t_i,pars,"mod"=mod,"x"=x,y0=y0,"primed"=isPrimed,"eff_y0"=eff_y0)
            print(pars)
            y <- model_trajectory(pars, tmpTimes)
            trajectories[tmpTimesI,index] <-  trajectories[tmpTimesI,index] + y[1:(length(y)-1)]
        }
        index <- index + 1
    }
    colnames(trajectories) <- strains
    return(trajectories)
}

















