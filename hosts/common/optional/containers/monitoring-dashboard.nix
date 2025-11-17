{ pkgs }:

pkgs.writeTextDir "system-overview.json" (
  builtins.toJSON {
    title = "System Overview";
    uid = "system-overview";
    tags = [
      "auto-provisioned"
      "system"
    ];
    timezone = "browser";
    schemaVersion = 16;
    refresh = "10s";

    panels = [
      {
        id = 1;
        title = "CPU Usage";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 0;
        };
        targets = [
          {
            expr = ''100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'';
            legendFormat = "CPU Usage";
            refId = "A";
          }
        ];
        options = {
          legend = {
            displayMode = "list";
            placement = "bottom";
          };
        };
        fieldConfig = {
          defaults = {
            unit = "percent";
            min = 0;
            max = 100;
            color = {
              mode = "palette-classic";
            };
          };
        };
      }

      {
        id = 2;
        title = "Memory Usage";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 0;
        };
        targets = [
          {
            expr = ''(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100'';
            legendFormat = "Memory Usage";
            refId = "A";
          }
        ];
        options = {
          legend = {
            displayMode = "list";
            placement = "bottom";
          };
        };
        fieldConfig = {
          defaults = {
            unit = "percent";
            min = 0;
            max = 100;
            color = {
              mode = "palette-classic";
            };
          };
        };
      }

      {
        id = 3;
        title = "Disk Usage";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 8;
        };
        targets = [
          {
            expr = ''(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100'';
            legendFormat = "Root Disk Usage";
            refId = "A";
          }
        ];
        options = {
          legend = {
            displayMode = "list";
            placement = "bottom";
          };
        };
        fieldConfig = {
          defaults = {
            unit = "percent";
            min = 0;
            max = 100;
            color = {
              mode = "palette-classic";
            };
          };
        };
      }

      {
        id = 4;
        title = "Network Traffic";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 8;
        };
        targets = [
          {
            expr = ''rate(node_network_receive_bytes_total[5m]) * 8'';
            legendFormat = "{{device}} RX";
            refId = "A";
          }
          {
            expr = ''rate(node_network_transmit_bytes_total[5m]) * 8'';
            legendFormat = "{{device}} TX";
            refId = "B";
          }
        ];
        options = {
          legend = {
            displayMode = "list";
            placement = "bottom";
          };
        };
        fieldConfig = {
          defaults = {
            unit = "bps";
            color = {
              mode = "palette-classic";
            };
          };
        };
      }

      {
        id = 5;
        title = "Container CPU Usage";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 24;
          x = 0;
          y = 16;
        };
        targets = [
          {
            expr = ''rate(node_systemd_unit_cpu_seconds_total{name=~"container@.*"}[5m]) * 100'';
            legendFormat = "{{name}}";
            refId = "A";
          }
        ];
        options = {
          legend = {
            displayMode = "table";
            placement = "right";
          };
        };
        fieldConfig = {
          defaults = {
            unit = "percent";
            min = 0;
            color = {
              mode = "palette-classic";
            };
          };
        };
      }

      {
        id = 6;
        title = "Container Memory Usage";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 24;
          x = 0;
          y = 24;
        };
        targets = [
          {
            expr = ''node_systemd_unit_memory_bytes{name=~"container@.*"} / 1024 / 1024'';
            legendFormat = "{{name}}";
            refId = "A";
          }
        ];
        options = {
          legend = {
            displayMode = "table";
            placement = "right";
          };
        };
        fieldConfig = {
          defaults = {
            unit = "decmbytes";
            min = 0;
            color = {
              mode = "palette-classic";
            };
          };
        };
      }
    ];
  }
)
