# Systemd report timer

The service and timer generate the static HTML report out of band.  They do not start a Postfilter daemon; filtering still occurs inside each nnrpd process.
