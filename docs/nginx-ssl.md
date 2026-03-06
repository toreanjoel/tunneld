# Nginx & SSL Architecture

How Tunneld manages reverse proxy configs and SSL certificates for local resources.

## Certificate Chain

```mermaid
graph TD
    subgraph Local PKI
        CA[Root CA - self-signed]
        RC1[resource-a.tunneld.sh cert]
        RC2[resource-b.tunneld.sh cert]
    end

    subgraph Client Device
        TRUST[Root CA installed in trust store]
        BROWSER[Browser]
    end

    CA -->|signs| RC1
    CA -->|signs| RC2
    TRUST -->|trusts| CA
    BROWSER -->|valid https| RC1
    BROWSER -->|valid https| RC2

    style CA fill:#7c3aed,color:#fff
    style TRUST fill:#10b981,color:#fff
```

1. **CertManager** generates a Root CA on first run (`/etc/tunneld/ca/`)
2. Users download and install the Root CA on their devices via `/download/ca`
3. When a resource is created, a cert is generated for `resourcename.tunneld.sh` signed by the Root CA
4. Nginx serves the resource over HTTPS with the signed cert
5. CertManager checks cert expiry every 6 hours and regenerates if needed

## Nginx Config Generation

```mermaid
flowchart TD
    A[Resource Created/Updated] --> B[Nginx.write_config]
    B --> C{Resource has pool?}
    C -->|Yes| D[Generate upstream block]
    C -->|No/Invalid| E[Skip - log error]
    D --> F[Generate server block]
    F --> G{Cert exists?}
    G -->|No| H[Generate SSL cert]
    G -->|Yes| I[Use existing cert]
    H --> I
    I --> J[Write /etc/nginx/conf.d/resource.conf]
    J --> K[Reload nginx]

    style A fill:#7c3aed,color:#fff
    style J fill:#374151,color:#fff
    style K fill:#374151,color:#fff
```

## Generated Config Structure

For each resource, nginx gets a config like:

```
upstream myapp {
    server 192.168.50.10:8080;
    server 192.168.50.11:8080;
}

server {
    listen 18000 ssl;
    server_name myapp.tunneld.sh;

    ssl_certificate     /etc/nginx/certs/myapp.crt;
    ssl_certificate_key /etc/nginx/certs/myapp.key;

    location / {
        proxy_pass http://myapp;
    }
}
```

Port 18000 is the shared public-facing nginx port. DNS hairpin entries point `myapp.tunneld.sh` to the gateway IP so subnet devices resolve it locally.
