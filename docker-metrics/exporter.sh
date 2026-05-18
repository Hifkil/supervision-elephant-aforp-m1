#!/bin/sh
set -eu

PROJECT="${COMPOSE_PROJECT_NAME:-supervision-elephant-aforp-m1}"
METRICS_FILE="/tmp/docker-metrics.prom"

to_bytes() {
  printf '%s\n' "$1" | awk '
    function mult(unit) {
      if (unit == "kB" || unit == "KB") return 1000
      if (unit == "MB") return 1000 * 1000
      if (unit == "GB") return 1000 * 1000 * 1000
      if (unit == "KiB") return 1024
      if (unit == "MiB") return 1024 * 1024
      if (unit == "GiB") return 1024 * 1024 * 1024
      return 1
    }
    {
      gsub(/ /, "", $0)
      match($0, /^([0-9.]+)([A-Za-z]*)$/, parts)
      if (parts[1] == "") print 0
      else printf "%.0f\n", parts[1] * mult(parts[2])
    }'
}

write_metrics() {
  tmp="${METRICS_FILE}.tmp"
  now="$(date +%s)"

  {
    echo "# HELP artemis_container_cpu_percent Docker container CPU usage percent by Compose service."
    echo "# TYPE artemis_container_cpu_percent gauge"
    echo "# HELP artemis_container_memory_percent Docker container memory usage percent by Compose service."
    echo "# TYPE artemis_container_memory_percent gauge"
    echo "# HELP artemis_container_network_receive_bytes_total Docker container received bytes since start."
    echo "# TYPE artemis_container_network_receive_bytes_total gauge"
    echo "# HELP artemis_container_network_transmit_bytes_total Docker container transmitted bytes since start."
    echo "# TYPE artemis_container_network_transmit_bytes_total gauge"
    echo "# HELP artemis_container_block_read_bytes_total Docker container block read bytes since start."
    echo "# TYPE artemis_container_block_read_bytes_total gauge"
    echo "# HELP artemis_container_block_write_bytes_total Docker container block written bytes since start."
    echo "# TYPE artemis_container_block_write_bytes_total gauge"
    echo "# HELP artemis_container_restart_count Docker container restart count."
    echo "# TYPE artemis_container_restart_count gauge"
    echo "# HELP artemis_container_running Docker container running state, 1 running and 0 stopped."
    echo "# TYPE artemis_container_running gauge"
    echo "# HELP artemis_volume_used_bytes Docker volume apparent disk usage in bytes."
    echo "# TYPE artemis_volume_used_bytes gauge"
    echo "# HELP artemis_volume_filesystem_size_bytes Filesystem size backing a mounted Docker volume."
    echo "# TYPE artemis_volume_filesystem_size_bytes gauge"
    echo "# HELP artemis_volume_filesystem_available_bytes Filesystem available bytes backing a mounted Docker volume."
    echo "# TYPE artemis_volume_filesystem_available_bytes gauge"
    echo "# HELP artemis_volume_filesystem_used_percent Filesystem used percent backing a mounted Docker volume."
    echo "# TYPE artemis_volume_filesystem_used_percent gauge"
    echo "# HELP artemis_docker_metrics_last_scrape_timestamp_seconds Last exporter collection timestamp."
    echo "# TYPE artemis_docker_metrics_last_scrape_timestamp_seconds gauge"
    echo "artemis_docker_metrics_last_scrape_timestamp_seconds ${now}"

    docker ps -a --filter "label=com.docker.compose.project=${PROJECT}" --format '{{.ID}}|{{.Names}}|{{.Label "com.docker.compose.service"}}' |
    while IFS='|' read -r id name service; do
      [ -n "$id" ] || continue
      [ -n "$service" ] || service="$name"

      running="$(docker inspect --format '{{if .State.Running}}1{{else}}0{{end}}' "$id" 2>/dev/null || echo 0)"
      restarts="$(docker inspect --format '{{.RestartCount}}' "$id" 2>/dev/null || echo 0)"
      echo "artemis_container_running{service=\"${service}\",container=\"${name}\"} ${running}"
      echo "artemis_container_restart_count{service=\"${service}\",container=\"${name}\"} ${restarts}"
    done

    docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}' |
    while IFS='|' read -r name cpu_raw mem_raw net block; do
      case "$name" in
        "${PROJECT}-"*) ;;
        *) continue ;;
      esac

      service="$(printf '%s\n' "$name" | sed "s/^${PROJECT}-//; s/-[0-9][0-9]*$//")"
      cpu="$(printf '%s\n' "$cpu_raw" | tr -d '%')"
      mem="$(printf '%s\n' "$mem_raw" | tr -d '%')"
      net_rx="$(to_bytes "$(printf '%s\n' "$net" | cut -d'/' -f1)")"
      net_tx="$(to_bytes "$(printf '%s\n' "$net" | cut -d'/' -f2)")"
      block_read="$(to_bytes "$(printf '%s\n' "$block" | cut -d'/' -f1)")"
      block_write="$(to_bytes "$(printf '%s\n' "$block" | cut -d'/' -f2)")"

      echo "artemis_container_cpu_percent{service=\"${service}\",container=\"${name}\"} ${cpu:-0}"
      echo "artemis_container_memory_percent{service=\"${service}\",container=\"${name}\"} ${mem:-0}"
      echo "artemis_container_network_receive_bytes_total{service=\"${service}\",container=\"${name}\"} ${net_rx}"
      echo "artemis_container_network_transmit_bytes_total{service=\"${service}\",container=\"${name}\"} ${net_tx}"
      echo "artemis_container_block_read_bytes_total{service=\"${service}\",container=\"${name}\"} ${block_read}"
      echo "artemis_container_block_write_bytes_total{service=\"${service}\",container=\"${name}\"} ${block_write}"
    done

    for path in /mnt/volumes/*; do
      [ -d "$path" ] || continue
      volume="$(basename "$path")"
      used_bytes="$(du -sk "$path" 2>/dev/null | awk '{ print $1 * 1024 }')"
      df -Pk "$path" 2>/dev/null | awk -v volume="$volume" -v used_bytes="${used_bytes:-0}" '
        NR == 2 {
          size = $2 * 1024
          available = $4 * 1024
          used_percent = size > 0 ? (($3 * 100) / $2) : 0
          printf "artemis_volume_used_bytes{volume=\"%s\"} %.0f\n", volume, used_bytes
          printf "artemis_volume_filesystem_size_bytes{volume=\"%s\"} %.0f\n", volume, size
          printf "artemis_volume_filesystem_available_bytes{volume=\"%s\"} %.0f\n", volume, available
          printf "artemis_volume_filesystem_used_percent{volume=\"%s\"} %.2f\n", volume, used_percent
        }'
    done
  } > "$tmp"

  mv "$tmp" "$METRICS_FILE"
}

serve_metrics() {
  while true; do
    {
      printf 'HTTP/1.1 200 OK\r\n'
      printf 'Content-Type: text/plain; version=0.0.4\r\n'
      printf 'Connection: close\r\n'
      printf '\r\n'
      cat "$METRICS_FILE"
    } | nc -l -p 8080
  done
}

while true; do
  write_metrics
  sleep 15
done &

while [ ! -s "$METRICS_FILE" ]; do
  sleep 1
done

serve_metrics
