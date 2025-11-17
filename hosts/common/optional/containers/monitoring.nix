# Monitoring stack container with Grafana, Prometheus, and exporters
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    (./networking.nix)
  ];

  hostSpec.networking.containerNetworks.monitoring.bridge = lib.mkDefault "mon-bridge";
  hostSpec.networking.containerNetworks.monitoring.subnet = lib.mkDefault "10.0.10.0/24";
  hostSpec.networking.containerNetworks.monitoring.gateway = lib.mkDefault "10.0.10.1";
  hostSpec.networking.containerNetworks.monitoring.containers.monitoring = lib.mkDefault 2;

  containers.monitoring =
    let
      net = lib.custom.mkContainerNetworkConfig config "monitoring" "monitoring";
      hostConfig = config;
    in
    {
      autoStart = true;

      bindMounts = {
        "/var/lib/prometheus2" = {
          hostPath = "/mnt/storage/monitoring/prometheus";
          isReadOnly = false;
        };
        "/var/lib/grafana" = {
          hostPath = "/mnt/storage/monitoring/grafana";
          isReadOnly = false;
        };
        # Mount host's /proc for node_exporter
        "/host/proc" = {
          hostPath = "/proc";
          isReadOnly = true;
        };
        # Mount host's /sys for node_exporter
        "/host/sys" = {
          hostPath = "/sys";
          isReadOnly = true;
        };
        # Mount host's root filesystem for disk metrics
        "/host/root" = {
          hostPath = "/";
          isReadOnly = true;
        };
        # Mount SOPS secrets
        "/run/secrets" = {
          hostPath = "/run/secrets";
          isReadOnly = true;
        };
      };

      privateNetwork = true;
      hostBridge = net.bridge;
      localAddress = "${net.containerIP}/${net.cidr}";

      forwardPorts = [
        {
          hostPort = 3001; # Grafana web UI
          containerPort = 3001;
        }
        {
          hostPort = 9090; # Prometheus
          containerPort = 9090;
        }
      ];

      config = lib.mkMerge [
        (lib.custom.mkContainerBaseConfig net)
        {
          environment.systemPackages = with pkgs; [
            prometheus
            grafana
          ];

          # Node Exporter
          services.prometheus.exporters.node = {
            enable = true;
            port = 9100;
            enabledCollectors = [
              "systemd"
              "processes"
              "cpu"
              "cpufreq"
              "meminfo"
              "diskstats"
              "filesystem"
              "netdev"
              "netstat"
              "thermal_zone"
              "loadavg"
              "pressure"
            ];
            # Use the bind-mounted host filesystem
            extraFlags = [
              "--path.procfs=/host/proc"
              "--path.sysfs=/host/sys"
              "--path.rootfs=/host/root"
              # Enable systemd unit resource metrics (CPU, memory per service)
              "--collector.systemd.unit-include=container@.*\\.service"
            ];
          };

          # Prometheus
          services.prometheus = {
            enable = true;
            port = 9090;
            listenAddress = "0.0.0.0";

            retentionTime = "30d";

            scrapeConfigs = [
              {
                job_name = "prometheus";
                static_configs = [
                  {
                    targets = [ "localhost:9090" ];
                    labels = {
                      instance = "prometheus";
                      environment = "production";
                    };
                  }
                ];
              }

              {
                job_name = "node";
                scrape_interval = "15s";
                static_configs = [
                  {
                    targets = [ "localhost:9100" ];
                    labels = {
                      instance = "host";
                      environment = "production";
                    };
                  }
                ];
              }
            ];
          };

          services.grafana = {
            enable = true;

            settings = {
              server = {
                http_addr = "0.0.0.0";
                http_port = 3001;
                domain = "localhost";
              };

              analytics = {
                reporting_enabled = false;
                check_for_updates = false;
              };

              security =
                let
                  # Get the first admin user from hostSpec
                  adminUsers = lib.filterAttrs (name: user: user.isAdmin or false) hostConfig.hostSpec.users;
                  firstAdmin = lib.head (lib.attrNames adminUsers);
                in
                {
                  admin_user = firstAdmin;
                  admin_password = "$__file{${hostConfig.sops.secrets."passwords/${firstAdmin}".path}}";
                };
            };

            provision = {
              enable = true;

              datasources.settings = {
                apiVersion = 1;
                datasources = [
                  {
                    name = "Prometheus";
                    type = "prometheus";
                    access = "proxy";
                    url = "http://localhost:9090";
                    isDefault = true;
                    jsonData = {
                      timeInterval = "15s";
                    };
                  }
                ];
              };

              dashboards.settings.providers = [
                {
                  name = "Auto-provisioned";
                  disableDeletion = false;
                  updateIntervalSeconds = 10;
                  allowUiUpdates = true;
                  options = {
                    path = "/etc/grafana-dashboards";
                    foldersFromFilesStructure = false;
                  };
                }
              ];
            };
          };

          # Provide dashboard JSON files to Grafana
          environment.etc."grafana-dashboards/system-overview.json".source =
            let
              dashboard = import ./monitoring-dashboard.nix { inherit pkgs; };
            in
            "${dashboard}/system-overview.json";

          networking.firewall.allowedTCPPorts = [
            3001
            9090
            9100
          ];

          systemd.tmpfiles.rules = [
            "d /var/lib/prometheus2 0755 prometheus prometheus -"
            "d /var/lib/grafana 0755 grafana grafana -"
            "d /var/lib/grafana/dashboards 0755 grafana grafana -"
          ];

          # Ensure services start in correct order
          systemd.services.grafana.after = [ "prometheus.service" ];
          systemd.services.grafana.wants = [ "prometheus.service" ];
        }
      ];
    };

  systemd = lib.mkMerge [
    (lib.custom.mkContainerSystemd "monitoring" { })
  ];

}
// (lib.custom.mkContainerDirs "monitoring" [
  "/mnt/storage/monitoring"
  "/mnt/storage/monitoring/prometheus"
  "/mnt/storage/monitoring/grafana"
])
