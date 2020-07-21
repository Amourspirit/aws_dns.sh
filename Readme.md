# AWS Route 53 Dynamic DNS

If you’ve got servers running at home or in the cloud such as on AWS, and you need to route a domain to them without a static IP address. Instead of paying for a dynamic DNS service, you can build your own using AWS Route 53.

If you want to set up dynamic DNS for a server or another non-AWS device that will have frequent IP address changes, scripting it is pretty easy. Route 53 has simple CLI commands that you can use to update DNS records from the command line; hooking this up to a cron job that watches for a change to the public IP address and runs the AWS CLI will get the job done.

Simplifing Route 53 Dynamic DNS

## Setting Up the AWS Side of Things

To get started, head over to the AWS Route 53 Management console. If you don’t have a domain, you can register one under “Registered Domains” for fairly cheap, usually just the price of the ICANN registration fee. If your domain isn’t currently in Route 53, you’ll have to transfer it over, which is an easy but lengthy process.

### Zone ID

Find or create the hosted zone for eac of your domains. For each domain or sub domain you will need to include the zone id in the `config.cfg` file show below.

**Figure 1:**  
![d0584bb8.png](https://i.postimg.cc/kXrBcLRV/d0584bb8.png)

It is recommend that each "domain/sub domain" have an `A` reccord so this script has something to reference. You can set this to something obviously not correct—255.255.255.255 would work—to test the script’s functionality.

### Configuraton file

Place all domains to update in your Route Configuration into a configuration file '~/.aws_dns/config.cfg`

```txt
mkdir -p ~/.aws_dns && touch ~/.aws_dns/config.cfg && nano ~/.aws_dns/config.cfg
```

The configuration sections names only requirement is that they arell all unique names. Only use alpha-numeric names and `_` (undersores) in a section name.  
The recommended naming convention is your domain name ( replace `.` with `_`) and the `type`. For instance `library.mydomain.tld.` for an `A` type record would have a section name of `[LIBRARY_MYDOMAIN_TLD_A]`

The `.` at the end of each domain name is optional.  
For instance `domain=library.mydomain.tld.` and `domain=library.mydomain.tld` are both valid.

Four setting can be used in each section.

* domain (the domain or sub-domain to update record for)
* type (the type of record such as `A` or `AAAA`)
* ttl (time to live in seconds)
* zone (zone id as seen in *figure 1*)

`domain` and `zone` are required for each section.  
`type` and `ttl` have defaults and are optional.

Defalut `type="A"`
Default `ttl=60`

Example cfg file

```ini
[LIBRARY_MYDOMAIN_TLD_A]
domain=library.mydomain.tld.
type="A"
ttl=60
zone=Z556URT733PKLW
[WP_MYDOMAIN_TLD_A]
domain=wp.mydomain.tld
type="A"
ttl=60
zone=Z556URT733PKLW
[LIBSTAFF_MYDOMAIN_TLD_A]
domain=libstaff.mydomain.tld.
[MYDOMAIN_TLD_A]
domain=mydomain.tld
type="A"
TTL=120
zone=Z556URT733PKLW
[myfantasticdomainname_com_a]
domain=myfantasticdomainname.com.
type="A"
TTL=300
zone=ZRTU7R4GGHWEC4
```

### AWS CLI

If `AWS CLI` is not installed you will need to install it.
To test if AWS is already installed you can run `# which aws && aws --version`

If installed you should see something similar to the following:

```txt
/usr/local/bin/aws
aws-cli/2.0.25 Python/3.7.3 Linux/5.4.0-1017-aws botocore/2.0.0dev29
```

If not installed You will need to set up the AWS CLI, which you can do with:

```txt
curl "https://d1vvhvl2y92vvt.cloudfront.net/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

## Automation

### Crontab automation

This script only sends updates to Route 54 when there is an ip address change. This script can be automated by adding it to a cron job. The example below when added to a cron job will run the script every 5 minutes.

```txt
*/5 * * * * /bin/bash $HOME/scripts/aws/awsdns_update.sh >/dev/null 2>&1
```

### Advanced Automation

Starting and running this script only when system reboots is sometimes all that is needed. This is the case in cloud computing such as with AWS when the server only gets a new IP Address when the server reboots ( if not assigned static IP Address such as Elastic IPs ). The issue is that the network is not ready when the system is booting up.

A solution is to run the script as a service for the system.

The following set up running this script as a system service.  **Warning** KNOW what you are doing before you attempt this.

Create a new system service named `awsdns_update` by running the following command:

```txt
systemctl edit --force --full awsdns_update.service
```

The above command will open the default text editor ( such as nano ). The first time you run the above command the editor will not contain any text.

```ini
[Unit]
Description=AWS dns update Service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/root/scripts/aws/aws_dns.sh

[Install]
WantedBy=multi-user.target
```

Save your changes and exit your editor.

Check the newly created service

```txt
$ systemctl status aws_dns.service
● aws_dns.service - AWS dns update Service
   Loaded: loaded (/etc/systemd/system/awsdns_update.service; disabled; vendor preset: enabled)
   Active: inactive (dead)
```

Now we can enable and test our service:

```txt
sudo systemctl enable awsdns_update.service
sudo systemctl start awsdns_update.service
```

Another status check shows the service is enabled

```txt
systemctl status awsdns_update.service
● duckdns_update.service - AWS dns update Service
     Loaded: loaded (/etc/systemd/system/awsdns_update.service; enabled; vendor preset: enabled)
     Active: inactive (dead) since Fri 2020-06-30 19:17:57 UTC; 31min ago
    Process: 494 ExecStart=/root/scripts/aws/awsdns_update.sh (code=exited, status=0/SUCCESS)
   Main PID: 494 (code=exited, status=0/SUCCESS)
```

## Requirements

`jq` - lightweight and flexible command-line JSON processor
`aws-cli` - Universal Command Line Interface for Amazon Web Services

## Special Thanks

Special thanks to [Anthony Heddings](https://www.cloudsavvyit.com/author/anthonyheddings/) for his article: [How to Roll Your Own Dynamic DNS with AWS Route 53](https://www.cloudsavvyit.com/3103/how-to-roll-your-own-dynamic-dns-with-aws-route-53/)
