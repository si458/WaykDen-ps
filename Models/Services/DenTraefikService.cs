using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
using Docker.DotNet.Models;
using WaykDen.Controllers;
using WaykDen.Utils;

namespace WaykDen.Models.Services
{
    public class DenTraefikService : DenService
    {
        private const string TRAEFIK_NAME = "traefik";
        private const string TRAEFIK_FILE_CMD = "--file";
        private const string TRAEFIK_FILE_PATH_CMD = "--configFile=/etc/traefik/traefik.toml";
        private const string TRAEFIK_LINUX_PATH = "/etc/traefik";
        private const string TRAEFIK_WINDOWS_PATH = "c:\\traefik";
        public string Tls = string.Empty;
        public string Entrypoints = "ws";
        public string WaykDenPort => this.DenConfig.DenTraefikConfigObject.WaykDenPort;
        public string Url => this.DenConfig.DenServerConfigObject.ExternalUrl;
        public DenTraefikService(DenServicesController controller)
        {
            this.DenServicesController = controller;
            this.Name = TRAEFIK_NAME;
            this.ImageName = this.DenConfig.DenImageConfigObject.DenTraefikImage;
            this.ExposedPorts.Add(this.WaykDenPort, new EmptyStruct());
            this.ExposedPorts.Add(this.DenConfig.DenTraefikConfigObject.ApiPort, new EmptyStruct());
            this.PortBindings.Add(this.WaykDenPort, new List<PortBinding>(){new PortBinding(){HostIP = "0.0.0.0", HostPort = this.WaykDenPort}});
            this.PortBindings.Add(this.DenConfig.DenTraefikConfigObject.ApiPort, new List<PortBinding>(){new PortBinding(){HostIP = "0.0.0.0", HostPort = this.DenConfig.DenTraefikConfigObject.ApiPort}});
            
            string mountPoint = this.DenConfig.DenDockerConfigObject.Platform == Platforms.Linux.ToString() ? TRAEFIK_LINUX_PATH : TRAEFIK_WINDOWS_PATH;
            string path = $"{this.DenServicesController.Path}traefik";
            this.Volumes.Add($"{path}:{mountPoint}");
            if(Directory.Exists(path))
            {
              Directory.Delete(path, true);
            }

            Directory.CreateDirectory(path);

            if(!string.IsNullOrEmpty(this.DenConfig.DenTraefikConfigObject.Certificate) && !string.IsNullOrEmpty(this.DenConfig.DenTraefikConfigObject.PrivateKey))
            {
              this.ImportCertificate();
              this.Entrypoints = "https";
            }

            string traefikToml = ExportDenConfigUtils.CreateTraefikToml(this);
            File.WriteAllText($"{path}/traefik.toml", traefikToml);
            
            this.Cmd.Add(TRAEFIK_FILE_CMD);
            this.Cmd.Add(TRAEFIK_FILE_PATH_CMD);
        }

        private string BuildTraefikToml(string externalUrl)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append(this.BuildConfig());
            return sb.ToString();
        }

        private string BuildConfig()
        {
            string traefikConfig = 
$@"
{{
  ""frontends"": {{
    ""lucid"": {{
      ""backend"": ""lucid"",
      ""passHostHeader"": true,
      ""entrypoints"": [
        ""{this.Entrypoints}""
      ],
      ""routes"": {{
        ""lucid"": {{
          ""rule"": ""PathPrefixStripRegex:/lucid""
        }}
      }}
    }},
    ""lucidop"": {{
      ""backend"": ""lucid"",
      ""passHostHeader"": true,
      ""entrypoints"": [
        ""{this.Entrypoints}""
      ],
      ""routes"": {{
        ""lucidop"": {{
          ""rule"": ""PathPrefix:/op""
        }}
      }}
    }},
    ""lucidauth"": {{
      ""backend"": ""lucid"",
      ""passHostHeader"": true,
      ""entrypoints"": [
        ""{this.Entrypoints}""
      ],
      ""routes"": {{
        ""lucidauth"": {{
          ""rule"": ""PathPrefix:/auth""
        }}
      }}
    }},
    ""router"": {{
      ""backend"": ""router"",
      ""passHostHeader"": true,
      ""entrypoints"": [
        ""{this.Entrypoints}""
      ],
      ""routes"": {{
        ""router"": {{
          ""rule"": ""PathPrefixStripRegex:/cow""
        }}
      }}
    }},""server"": {{
      ""backend"": ""server"",
      ""passHostHeader"": true,
      ""entrypoints"": [
        ""{this.Entrypoints}""
      ]
    }}
  }},
  ""backends"": {{
    ""lucid"": {{
      ""servers"": {{
        ""lucid"": {{
          ""url"": ""http://den-lucid:4242""
        }}
      }}
    }},
    ""router"": {{
      ""servers"": {{
        ""router"": {{
	        ""url"": ""http://den-router:4491""
        }}
      }}
    }},
    ""server"": {{
      ""servers"": {{
        ""server"": {{
	        ""url"": ""http://den-server:10255""
        }}
      }}
    }}
  }}
}}
";
            return traefikConfig;
        }

        public async Task<bool> CurlTraefikConfig()
        {
          try
          {
            using(var httpClient = new HttpClient())
            {
                string port =  this.DenConfig.DenTraefikConfigObject.ApiPort;
                using (var request = new HttpRequestMessage(new HttpMethod("PUT"), $"http://127.0.0.1:{port}/api/providers/rest"))
                {
                    request.Content = new StringContent(this.BuildConfig(), Encoding.UTF8);
                    var response = httpClient.SendAsync(request);
                    response.Wait();
                    return (await response).StatusCode == HttpStatusCode.OK;
                }
            }
          }
          catch(Exception)
          {
            throw new Exception("Problem with Traefik. Try to restart WaykDen.");
          }
        }

        private void ImportCertificate()
        {
          this.DenServicesController.Path.TrimEnd(System.IO.Path.DirectorySeparatorChar);
          string path = $"{this.DenServicesController.Path}{System.IO.Path.DirectorySeparatorChar}traefik";
          File.WriteAllText($"{path}{System.IO.Path.DirectorySeparatorChar}traefik.cert", this.DenConfig.DenTraefikConfigObject.Certificate);
          File.WriteAllText($"{path}{System.IO.Path.DirectorySeparatorChar}traefik.key", this.DenConfig.DenTraefikConfigObject.PrivateKey);
          string https = 
@"[entryPoints.https.tls]
    [[entryPoints.https.tls.certificates]]
    certFile = ""{0}/traefik.cert""
    keyFile = ""{0}/traefik.key""
    ";
              string mountPoint = this.DenConfig.DenDockerConfigObject.Platform == Platforms.Linux.ToString() ? TRAEFIK_LINUX_PATH : TRAEFIK_WINDOWS_PATH;
              this.Tls = string.Format(https, mountPoint);
        }
    }
}