library(ProjectTemplate)
load.project()

set.seed(42)
num_cores <- 16

train_pct <- 2/3
num_iterations <- 100

data_sets <- c('chiaretti', 'chowdary', 'nakayama', 'shipp', 'singh', 'tian')

sim_config <- rep(data_sets, each=num_iterations)

flog.logger("sim", INFO, appender=appender.file('sim-microarray.log'))

results <- mclapply(seq_along(sim_config), function(i) {
  # Load data and randomly partition into training/test data sets.
  data_set <- sim_config[i]

  set.seed(i)
  data <- load_microarray(data_set)
  data$x <- as.matrix(data$x)
  rand_split <- rand_partition(y=data$y, num_partitions=1,
                               train_pct=train_pct)[[1]]
  train_x <- as.matrix(data$x[rand_split$training, ])
  train_y <- data$y[rand_split$training]
  test_x <- as.matrix(data$x[rand_split$test, ])
  test_y <- data$y[rand_split$test]

  # Apply Dudoit's variable selection with 1000 variables to reduce runtime.
  top_features <- dudoit(train_x, train_y, num_variables=1000)
  train_x <- train_x[, top_features]
  test_x <- test_x[, top_features]

  flog.info("Training Data: (Observations, Dimension): (%s, %s) -- Data Set: %s -- Sim Config: %s of %s",
            nrow(train_x), ncol(train_x), data_set, i, length(sim_config), name="sim")

  flog.info("Test Data: (Observations, Dimension): (%s, %s) -- Data Set: %s -- Sim Config: %s of %s",
            nrow(test_x), ncol(test_x), data_set, i, length(sim_config), name="sim")

  # Removes the loaded data from memory and then garbage collects.
  rm(data)
  gc(reset=TRUE)

  # Sets the prior probabilities as equal
  num_classes <- nlevels(train_y)
  prior_probs <- rep(1, num_classes) / num_classes

  # Random Forest
  rf_errors <- try({
    rf_out <- randomForest(x=train_x,
                           y=train_y,
                           ntree=250,
                           maxnodes=100)
    rf_predict <- predict(rf_out, test_x)
    mean(rf_predict != test_y)
  })
  rm("rf_out")

  flog.info("Random Forest Error Rate: %s -- Data Set: %s -- Sim Config: %s of %s",
            rf_errors, data_set, i, length(sim_config), name="sim")

  # Witten and Tibshirani (2011) - JRSS B
  Witten_errors <- try({
      Witten_out <- Witten_Tibshirani(train_x=train_x,
                                      train_y=train_y,
                                      test_x=test_x)
      mean(Witten_out$predictions != test_y)
  })
  rm("Witten_out")

  flog.info("Witten Error Rate: %s -- Data Set: %s -- Sim Config: %s of %s",
            Witten_errors, data_set, i, length(sim_config), name="sim")

  # Guo, Hastie, and Tibshirani (2007) - Biostatistics
  Guo_errors <- try({
      Guo_out <- Guo(train_x=train_x,
                     train_y=train_y,
                     test_x=test_x,
                     prior=prior_probs)
      mean(Guo_out != test_y)
  })
  rm("Guo_out")

  flog.info("Guo Error Rate: %s -- Data Set: %s -- Sim Config: %s of %s",
            Guo_errors, data_set, i, length(sim_config), name="sim")

  # HDRDA - Ridge
  hdrda_ridge_errors <- try({
      cv_out <- hdrda_cv(x=train_x,
                         y=train_y,
                         prior=prior_probs)
      hdrda_ridge <- list(lambda=cv_out$lambda, gamma=cv_out$gamma)
      flog.info("HDRDA Ridge. Lambda: %s. Gamma: %s -- Sim Config: %s of %s",
                cv_out$lambda, cv_out$gamma, i, length(sim_config), name="sim")
      mean(predict(cv_out, test_x)$class != test_y)
  })
  rm("cv_out")

  flog.info("HDRDA Ridge Error Rate: %s -- Data Set: %s -- Sim Config: %s of %s",
            hdrda_ridge_errors, data_set, i, length(sim_config), name="sim")

  # HDRDA - Convex
  hdrda_convex_errors <- try({
      cv_out <- hdrda_cv(x=train_x,
                         y=train_y,
                         prior=prior_probs,
                         num_gamma=21,
                         shrinkage_type="convex")
      hdrda_convex <- list(lambda=cv_out$lambda, gamma=cv_out$gamma)
      flog.info("HDRDA Convex. Lambda: %s. Gamma: %s -- Sim Config: %s of %s",
                cv_out$lambda, cv_out$gamma, i, length(sim_config), name="sim")
      mean(predict(cv_out, test_x)$class != test_y)
  })
  rm("cv_out")

  flog.info("HDRDA Convex Error Rate: %s -- Data Set: %s -- Sim Config: %s of %s",
            hdrda_convex_errors, data_set, i, length(sim_config), name="sim")

  # Tong, Chen, and Zhao (2012) - Bioinformatics
  Tong_errors <- try({
      Tong_out <- dlda(x=train_x,
                       y=train_y,
                       est_mean="tong",
                       prior=prior_probs)
      mean(predict(Tong_out, test_x)$class != test_y)
  })
  rm("Tong_out")

  flog.info("Tong Error Rate: %s -- Data Set: %s -- Sim Config: %s of %s",
            Tong_errors, data_set, i, length(sim_config), name="sim")

  # Pang, Tong, and Zhao (2009) - Bioinformatics
  Pang_errors <- try({
      Pang_out <- sdlda(x=train_x,
                        y=train_y,
                        prior=prior_probs)
      mean(predict(Pang_out, test_x)$class != test_y)
  })
  rm("Pang_out")

  flog.info("Pang Error Rate: %s -- Data Set: %s -- Sim Config: %s of %s",
            Pang_errors, data_set, i, length(sim_config), name="sim")

  error_rates <- list(
    Guo=Guo_errors,
    HDRDA_Ridge=hdrda_ridge_errors,
    HDRDA_Convex=hdrda_convex_errors,
    Pang=Pang_errors,
    Random_Forest=rf_errors,
    Tong=Tong_errors,
    Witten=Witten_errors
  )

  list(error_rates=error_rates,
       data_set=data_set,
       hdrda_ridge=hdrda_ridge,
       hdrda_convex=hdrda_convex
  )
}, mc.cores=num_cores)

results <- list(sim_results=results,
                train_pct=train_pct,
                num_iterations=num_iterations)

save(results, file='data/results-microarray.RData')
