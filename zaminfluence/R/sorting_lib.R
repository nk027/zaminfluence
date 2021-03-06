library(dplyr)


# The role of this library is to process the gradient dataframe from
# python_lib.R:GetTargetRegressorGrads to calculate adversarial removal
# sets for changing the sign and significance of the target regressor.
#
#

#' Return the $Gamma_alpha$ quantity.
#'
#' @param influence_dfs `r docs$influence_dfs`
#' @return The <base_vals> attribute, having checked that both pos and neg
#' have the same values.
#' @export
SafeGetBaseVals <- function(influence_dfs) {
    base_vals <- attr(influence_dfs$pos, "base_vals")
    if (max(abs(base_vals - attr(influence_dfs$neg, "base_vals"))) > 1e-8) {
        stop("base_vals do not match.")
    }
    return(base_vals)
}


#' Sort a gradient dataframe to effect a change in the direction of
#' <change_sign> using <influence_col>.  Append columns for the number and
#' proportion of rows removed.
SortInfluenceDf <- function(influence_df, influence_col, change_sign) {
  change_sign <- sign(change_sign)
  if (change_sign == 0) {
    stop("change_sign must be nonzero.")
  }
  n_obs <- attr(influence_df, "n_obs")
  obs_per_row_col <- attr(influence_df, "obs_per_row_col")
  sorted_df <-
    influence_df %>%
    ungroup() %>%
    arrange(change_sign * get(influence_col)) %>%
    mutate(num_removed=cumsum(get(obs_per_row_col))) %>%
    mutate(prop_removed=num_removed / n_obs)
  return(sorted_df)
}


#' Calculate the estimated cumulative effects for a sorted gradient dataframe.
AccumulateInfluenceDf <- function(df,
                                  influence_cols,
                                  base_vals,
                                  change_colnames,
                                  estimate_colnames) {
  if (!(length(base_vals) == length(influence_cols))) {
    stop("base_vals and influence_cols must be the same length.")
  }
  for (i in 1:length(influence_cols)) {
    base_val <- base_vals[i]
    col <- influence_cols[i]
    # Recall that we are removing points, so the effect is -1 * influence.
    df[[change_colnames[i]]] <- -1 * cumsum(df[[col]])
    df[[estimate_colnames[i]]] <- df[[change_colnames[i]]] + base_val
  }

  return(df)
}


#' Prepend a row for removing no rows and effecting no change to a sorted
#' gradient dataframe.
PrependZeroRemoved <- function(df, keep_cols) {
  zero_df <- data.frame(num_removed=0, prop_removed=0)
  for (col in keep_cols) {
    zero_df[[col]] <- 0
  }
  return(bind_rows(df, zero_df) %>% arrange(num_removed))
}


#'Sort and aggregate a gradient dataframe for a particular kind of change.
#'
#' @param grad_df `r docs$grad_df`
#' @param sort_col Which column to sort by, typically an influence column.
#' @param change_sign The sign change that is to be effected by removing rows.
#' @param influence_cols `r docs$influence_cols`
#'
#' @return `r docs$sort_return`
#'
#' @export
SortAndAccumulateForSign <- function(grad_df, sort_col, change_sign,
                                     influence_cols) {
  change_sign <- sign(change_sign)
  if (change_sign == 0) {
    stop("change_sign must be nonzero.")
  }
  base_vals <- attr(grad_df, "base_vals")
  infl_df <-
    SortInfluenceDf(
      grad_df,
      influence_col=sort_col,
      change_sign=change_sign) %>%
    PrependZeroRemoved(paste0(influence_cols, "_grad")) %>%
    AccumulateInfluenceDf(
      influence_cols=paste0(influence_cols, "_grad"),
      base_vals=base_vals,
      change_colnames=paste0(influence_cols, "_change"),
      estimate_colnames=paste0(influence_cols, "_est")) %>%
      CopyGradAttributes(grad_df)
  attr(infl_df, "sort_col") <- sort_col
  attr(infl_df, "change_sign") <- change_sign
  attr(infl_df, "influence_cols") <- influence_cols
  return(infl_df)
}


#' Sort and process a gradient dataframe to approximate adversarial removal sets.
#'
#' @param grad_df `r docs$grad_df`
#' @param influence_cols `r docs$influence_cols_default`
#'
#' @return A list of lists, ultimately containing dataframes, of observations
#' sorted for various types of adversarial removal.  The list entries
#' `sign` and `sig` refer to changing sign and significance of the target regressor,
#' and entries `pos` and `neg` refer to increasing or decreasing the value.  See
#' [SortAndAccumulateForSign()] for details of the dataframe.
#'
#' @export
SortAndAccumulate <- function(grad_df, influence_cols=NULL) {
  influence_cols <- names(attr(grad_df, "base_vals"))
  LocalSortAndAccumulateForSign <- function(sort_col, change_sign) {
    SortAndAccumulateForSign(
      grad_df,
      sort_col=sort_col,
      influence_cols=influence_cols,
      change_sign=change_sign)
  }
  result <- list(
    sign=list(
      pos=LocalSortAndAccumulateForSign("beta_grad", change_sign=1),
      neg=LocalSortAndAccumulateForSign("beta_grad", change_sign=-1)),
    sig=list(
      pos=LocalSortAndAccumulateForSign("beta_pzse_grad", change_sign=1),
      neg=LocalSortAndAccumulateForSign("beta_mzse_grad", change_sign=-1))
  )
  return(result)
}
