# bpsync
Backup script for BigIP systems.

1. Replace `myuser` with the user that will connect to the BigIP systems (passwordless).
2. Replace `postfix` with your domain, e.g. .intranet.google.com
3. Put all your servers in `servers`.
4. Setup a nightly cronjob for the script to run.
