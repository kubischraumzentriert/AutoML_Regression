suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
})

run_timed_benchmark <- function(tasks, learners, resampling, measures) {
  benchmark_results <- list()
  result_rows <- list()
  score_rows <- list()
  run_id <- 1L

  for (task in tasks) {
    task_resampling <- resampling$clone(deep = TRUE)
    task_resampling$instantiate(task)

    for (learner in learners) {
      design <- data.table(
        task = list(task),
        learner = list(learner),
        resampling = list(task_resampling$clone(deep = TRUE))
      )

      timing <- system.time({
        benchmark_result <- benchmark(design)
      })

      result <- benchmark_result$aggregate(measures = measures)
      result[, elapsed_seconds := as.numeric(timing[["elapsed"]])]
      scores <- benchmark_result$score(measures = measures)
      scores[, elapsed_seconds := as.numeric(timing[["elapsed"]])]

      benchmark_results[[run_id]] <- benchmark_result
      result_rows[[run_id]] <- result
      score_rows[[run_id]] <- scores
      run_id <- run_id + 1L
    }
  }

  list(
    results = rbindlist(result_rows, fill = TRUE),
    scores = rbindlist(score_rows, fill = TRUE),
    benchmarks = benchmark_results
  )
}
