#include <Rcpp.h>
#include "model.h"
using namespace Rcpp;


//' Observation error matrix solver
//' 
//' Calculates a single likelihood for an observed titre given the true titre and observation error parameters
//' @param actual integer for the believed true titre
//' @param obs integer for the observed titre
//' @param S probability of observing the true titre
//' @param EA probability of a + or - 1 observation
//' @param MAX_TITRE integer for the maximum observable titre
//' @return a single probability value
//' @export
//' @useDynLib antibodyKinetics
//[[Rcpp::export]]
double obs_error(int actual, int obs, double S, double EA, int MAX_TITRE){
  if(actual == (MAX_TITRE) && obs == (MAX_TITRE)) return(S + EA/2.0 - (1.0/(MAX_TITRE-2.0))*(1.0-S-EA));
  else if(actual==0 && obs==0) return(S + EA/2.0 - (1.0/(MAX_TITRE-2.0))*(1.0-S-EA));
  else if(actual==obs) return(S);
  else if(actual == (obs + 1) || actual==(obs-1)) return(EA/2.0);
  return((1.0/(MAX_TITRE-2.0))*(1.0-S-EA));
}

//' Observation error function
//'
//' Given a vector of believed true titres and a vector of observed data, 
//' calculates a likelihood based on a given observation error matrix
//' @param y NumericVector of believed true titres
//' @param data NumericVector of observed data, matching y
//' @param params observation error matrix paramters in order S, EA, MAX_TITRE
//' @export
//' @useDynLib antibodyKinetics
//[[Rcpp::export]]
double obs_likelihood(NumericVector y, NumericVector data, NumericVector params){
  double ln = 0;
  int MAX_TITRE = params(2);
  for(int i = 0; i < y.length();++i){
    if(y(i) < 0) y(i) = 0;
    if(y(i) >= MAX_TITRE) y(i) = MAX_TITRE;
    ln += log(obs_error(floor(y(i)), floor(data(i)),params(0),params(1),MAX_TITRE));
  }
  return ln;
}

//' Posterior calculation cpp implementation
//'
//' Solves the antibody kinetics model for given parameters, and then calculates a likelihood
//' for the given data set. This is a complex function, so should only really be called through
//' \code{\link{create_model_group_func_cpp}}. Look at this code to really understand what's
//' going on! The key confusing thing is that the length of the vectors has to match the number
//' of rows from the overall parameter table
//' @param pars the vector of model parameters as in parTab
//' @param times the vector of times to solve the model over
//' @param groups IntegerVector of the exposure groups (starting at group 1)
//' @param individuals IntegerVector with number of individuals in each group (to be used to index the data matrix)
//' @param strains IntegerVector of strains involved in exposures (ie. observed and exposed), starting at 1
//' @param exposure_types IntegerVector of exposure types matching the exposure table. "all"=0, "infection"=1,"vacc"=2,"adj"=3,"mod"=4,"NA"=5
//' @param exposure_strains IntegerVector of exposure strains for each exposure. Note that this goes from 1 to 5.
//' @param measured_strains IntegerVector of measured strains for each exposure (ie. second index in cross reactivity calculation)
//' @param exposure_orders IntegerVector of order of exposures
//' @param exposure_primes IntegerVector of whether each exposure was primed or not (for priming modifier)
//' @param exposure_indices IntegerVector of indices describing which parTab rows relate to exposure parameters
//' @param cr_inds IntegerVector of indices describing which parTab rows relate to cross reactivity parameters
//' @param par_type_ind IntegerVector of indices describing which parTab rows relate to model parameters
//' @param order_indices IntegerVector of indices describing which parTab rows relate to order modifer parameters
//' @param exposure_i_lengths IntegerVector of lengths describing the size of blocks in the exposure_indices vector that relate to each exposure group
//' @param par_lengths IntegerVector of lengths describing the size of blocks in the par_type_ind vector that relate to each exposure type
//' @param cr_lengths IntegerVector of lengths describing the size of blocks in the cr_ind vector that relate to each strain
//' @param data NumericMatrix of antibody titre data. Each row should be complete observations of titres against a given strain for a given group. If we have 5 strains measured and 5 groups, rows 1:5 should be titres in group 1, rows 6:10 titres in group 3 etc. If more than 1 individual in each group, multiply these criteria by number of inidividuals in that group (ie., rows 1:15 for group 1)
//' @return a single likelihood of observing the data given the model parameters
//' @export
//' @useDynLib antibodyKinetics
//[[Rcpp::export]]
double posterior_func_group_cpp(NumericVector pars, NumericVector times, 
				IntegerVector groups, IntegerVector individuals,
				IntegerVector strains, IntegerVector exposure_types, 
				IntegerVector exposure_strains, IntegerVector measured_strains, 
				IntegerVector exposure_orders, IntegerVector exposure_primes,
				IntegerVector exposure_indices, IntegerVector cr_inds,
				IntegerVector par_type_ind, IntegerVector order_indices,
				IntegerVector exposure_i_lengths, IntegerVector par_lengths, 
				IntegerVector cr_lengths, NumericMatrix data){
  int group;
  int strain;
  int A, B, type, order, exposure_strain;
  double t_i, mod, cr,isPrimed;
  double ln = 0;
  IntegerVector tmp_exposures;
  NumericVector fullPars;
  NumericMatrix results(strains.size()*groups.size(), times.size());
  NumericVector y;
  int index_data = 0;
  int index_model = 0;

  // For each group
  for(int i = 0; i < groups.size(); ++i){
    group = groups[i];

    // Get the range of indices for exposure parameters corresponding to this exposure
    A = exposure_i_lengths[i];
    B = exposure_i_lengths[i+1] - 1;
    tmp_exposures = exposure_indices[Range(A,B)];

    // For each measured strain
    for(int j = 0; j < strains.size(); ++j){
  // Strains have to be 0 indexed
      strain = strains[j] -1;

      // For each exposure, calculate the antibody kinetics for this strain
      for(int k = 0; k < tmp_exposures.size(); ++k){

	// Get infection time, the order of this infection and what the exposure strain was.
	// If we want to limit to non-additive kinetics, then here I'd need to subset the times
	// vector by those times after t_i and before the next t_i (or the end of the times vector)
	t_i = pars[tmp_exposures[k]];
	order = exposure_orders[tmp_exposures[k]] - 1;
	exposure_strain = exposure_strains[tmp_exposures[k]] - 1;
	mod = pars[order_indices[order]];
	isPrimed = exposure_primes[tmp_exposures[k]];

	// This is just matrix indexing of a vector
	cr = pars[cr_inds[cr_lengths[strain] + exposure_strain]];

	// Again, need to zero index exposure strains
	type = exposure_types[tmp_exposures[k]] - 1;

	// Use these toget subset of parameters that correspond to this infection
	// type
	A = par_lengths[type];
	B = par_lengths[type+1] - 1;

	// Combine parameters
	fullPars = pars[par_type_ind[Range(A,B)]];
	fullPars.push_back(isPrimed);
	fullPars.push_back(mod);
	fullPars.push_back(cr);
	fullPars.push_back(t_i);

	// Solve modle for this single strain and exposure
	y = model_trajectory_cpp(fullPars, times);

	// Additive antibody levels
	for(int ii = 0; ii < y.size(); ++ii){
	  results(index_model, ii) += y[ii];
	}
      }

      // Calculate the likelihood of observing the data given that the model calculated
      // trajectory was the true trajectory. Do this for each individual
      for(int jj = 0; j < individuals[i]; ++jj){
	ln += obs_likelihood(results(index_model,_), data(index_data,_), fullPars);
	index_data++;
      }
      index_model++;
    }
  }
  return ln;
}