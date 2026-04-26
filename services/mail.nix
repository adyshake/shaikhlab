{
  config,
  vars,
  ...
}: {
  # System-wide SMTP relay so services (smartd, mdmonitor, systemd timers,
  # cron jobs, `mail root`, etc.) can deliver email. Uses msmtp as a drop-in
  # sendmail replacement at /run/wrappers/bin/sendmail. Outbound mail goes
  # through MXroute (heracles.mxrouting.net:465, SSL/TLS on connect).

  sops.secrets."mxroute-smtp-password" = {};

  programs.msmtp = {
    enable = true;
    # Installs /run/wrappers/bin/sendmail → msmtp.
    setSendmail = true;

    defaults = {
      aliases = "/etc/aliases";
      tls = "on";
      tls_trust_file = "/etc/ssl/certs/ca-certificates.crt";
      # Log to the journal instead of a file — keeps impermanence simple.
      syslog = "LOG_MAIL";
    };

    accounts.default = {
      host = "heracles.mxrouting.net";
      port = 465;
      # Port 465 is SSL/TLS on connect, not STARTTLS.
      tls_starttls = "off";
      auth = "on";
      user = vars.userEmail;
      from = vars.userEmail;
      passwordeval = "cat ${config.sops.secrets."mxroute-smtp-password".path}";
    };
  };

  # Funnel local root mail (mdmonitor, systemd, sudo, etc.) to a real inbox.
  environment.etc."aliases".text = ''
    root: ${vars.userEmail}
  '';
}
