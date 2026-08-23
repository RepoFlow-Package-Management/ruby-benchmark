# Ruby Version Benchmark

This benchmark measures how the same Ruby program performs across Ruby 2.7 through Ruby 4.0.

Each version runs in its official Docker image. The suite uses fresh process repeats and produces raw JSON, a Markdown report, and an HTML dashboard.

## Workloads

The application workload combines JSON, SHA256, Base64, a shared cache, threads, and allocation pressure.

Microbenchmarks cover JSON parsing and generation, SHA256, Base64, regular expressions, integer sorting, Hash churn, Marshal, and zlib.

Light and heavy profiles change the payload size and allocation pressure.

## Requirements

Docker and Python 3.9 or newer are required. Ruby does not need to be installed locally.

## Full benchmark

```bash
bash scripts/bench_docker.sh --pull
```

The full run uses five repeats. The application has a 20 second warmup and a 10 minute measurement. Microbenchmarks have a 5 second warmup and a 10 second measurement.

List the resolved images with `bash scripts/bench_docker.sh --list-images`.

Results are written to `results`, which is ignored by Git. Run the benchmark on an idle machine with a fixed Docker CPU and memory allocation.

## License

MIT
