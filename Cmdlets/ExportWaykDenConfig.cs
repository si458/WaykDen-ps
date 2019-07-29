using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using WaykDen.Controllers;

namespace WaykDen.Cmdlets
{
    [Cmdlet("Export", "WaykDenConfig")]
    public class ExportWaykDenConfig : WaykDenConfigCmdlet
    {
        private const string DOCKER_COMPOSE_FILENAME = "docker-compose.yml";
        private const string TRAEFIK_TOML_FILENAME = "traefik.toml";
        [Parameter(HelpMessage = "Path where to export WaykDen configuration.")]
        public string ExportPath {get; set;} = string.Empty;
        [Parameter(HelpMessage = "Export in a docker-compose.yaml file. (A traefik.toml will also be exported)")]
        public SwitchParameter DockerCompose {get; set;} = false;
        [Parameter(HelpMessage = "Export traefik.toml only for Traefik.")]
        public SwitchParameter TraefikToml {get; set;} = false;
        public ExportWaykDenConfig()
        {
        }

        protected override void ProcessRecord()
        {
            try
            {
                DenServicesController denServicesController = new DenServicesController(this.Path, this.Key);
                denServicesController.OnLog += this.OnLog;
                denServicesController.OnError += this.OnError;

                if(string.IsNullOrEmpty(this.ExportPath))
                {
                    this.ExportPath = this.SessionState.Path.CurrentLocation.Path;
                }

                this.ExportPath.TrimEnd(System.IO.Path.DirectorySeparatorChar);
                if(DockerCompose)
                {
                    string traefikExportPath = $"{this.Path}{System.IO.Path.DirectorySeparatorChar}traefik/";
                    Directory.CreateDirectory(traefikExportPath);
                    string[] exports = denServicesController.CreateDockerCompose();
                    File.WriteAllText($"{this.ExportPath}{System.IO.Path.DirectorySeparatorChar}{DOCKER_COMPOSE_FILENAME}", exports[0]);
                    File.WriteAllText($"{traefikExportPath}{TRAEFIK_TOML_FILENAME}", exports[1]);
                }
                else if(TraefikToml)
                {
                    File.WriteAllText($"{this.Path}{System.IO.Path.DirectorySeparatorChar}traefik{System.IO.Path.DirectorySeparatorChar}{TRAEFIK_TOML_FILENAME}", denServicesController.CreateTraefikToml());
                }
            }
            catch(Exception e)
            {
                this.OnError(e);
            }
        }
    }
}