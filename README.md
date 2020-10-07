# Setup a decent web-server on the internets
This is what I (personally) do right after (re-) deploying a new debian-based server somewhere on the internets (be it bare-metal, some cheap VPS or similar).

## Lock down SSH
Before doing anything, let's create a ssh-key-pair if you haven't got one already
```shell_script
[local] $ ssh-keygen -b 4096 -t rsa
```
Remember the passphrase well, remember the file-name you saved it as well.

* Now, let's login to our newly installed debian remote.
  ```shell_script
  [local] $ ssh root@<SERVER_IP>
  ```

* On the remote-host, create a new sudo-user.
  ```shell_script
  [remote] $ useradd -m -G sudo adm -s /bin/bash <USERNAME>
  ```
  Assign a password
  ```shell_script
  [remote] $ passwd <USERNAME>
  ```
  Logout
  ```shell_script
  [remote] $ exit
  ```

* Copy the RSA key from local to remote
  ```shell_script
  [local] $ ssh-copy-id -i ~/.ssh/<RSA_KEY>.pub <USERNAME>@<SERVER_IP>
  ```

* Lock down sshd

  * Login as the new sudo user
    ```shell_script
    [local] ssh <USERNAME>@<SERVER_IP>
    ```
  
  At this stage, you may want to change/fix your hostname.
  Make sure, that the name in ```/etc/hostname``` matches the loopback-entry (127.0.0.1) in ```/etc/hosts``` otherwise, you'll get pesky "Unable to resolve hostname..." errors.

  * Now, it's time to checkout this repo on the remote as well...
    ```shell_script
    [remote] $ git clone https://github.com/pskrypalle/web-server.git \
      && cd web-server
    ```
  * Actually lock down ssh

    The following script revokes the possibility to login with credientials, denies login as root and disables PAM authentication.
    ```shell_script
    [remote] $ ./lock-ssh.sh
    ```
  * Now, restart sshd
    ```shell_script
    [remote] $ sudo systemctl restart sshd
    ```
  * Logout.
    ```shell_script
    [remote] $ exit
    ```

## Update system
Now that we can be sure that noone's going to disurb us, first things first.

```shell_script
[remote] $ sudo apt update && sudo apt full-upgrade
```

## Setup domain with cloudflare
To get going, we'll be setting up things in cloudflare's awesome web-ui first, before coming back into our beloved terminal.

If you don't have an account at cloudflare yet, this would be a great time to set one up. I am going to assume that you already have setup a domain (that you own of course) with cloudflare, have updated the name-servers on your registrar to use cloudflare's name-servers and that we're good to go.

### DNS
Before we can dive into setting up SSL for our little webserver, we need to setup our domain to be proxied by cloudflare. Over at ```https://dash.cloudflare.com``` (provided you already have an account, if not, what are you doing here?) go to DNS settings and create the following DNS entries:

| type  | name            | content     | TTL  | comment                            |
|-------|-----------------|-------------|------|------------------------------------|
| A     | DOMAIN     | SERVER_IP   | auto | root A record                      |
| A     | www.DOMAIN | SERVER_IP   | auto | root A record including www-prefix |
| CNAME | ssh             | DOMAIN | auto | alias for ssh (used later)         |

### SSL/TLS
As a last thing we need to tell cloudflare that we want to encrypt connections to and from our web-server end-to-end. This requires a trusted CA (certificate authority) or cloudflare origin to issue the certificates we host on our web-server.

That's fine, we'll be setting this up next. So go into the SSL/TLS settings on the cloudflare dashboard (```https://dash.cloudflare.com```) and chose option *Full (strict)*.

## nginx basics 
Okay, back to the terminal we go. Let's actually install some software for once.
```shell_script
[remote] $ sudo apt install nginx
``` 
Copy nginx' default profile to one to modify for our needs. You can choose ```PROFILENAME``` freely, I usually use the root-domain-name this server answers to on port ```80```.
```shell_script
[remote] $ sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/<PROFILENAME>
```
If you're like me, you'll probably want to remove all the pesky comments in the file we just copied. To do that in ```vim```, just run ```:g/^\s*#/d```

Edit the file you just copied, so that it looks like this:
```
server {

	listen 80 ;
	listen [::]:80 ;

	root /var/www/<PROFILENAME>;

	index index.html index.htm; 

	server_name <DOMAIN> www.<DOMAIN>; 

	location / {
		try_files $uri $uri/ =404;
	}

}
```

Now that we've told nginx that there's a site available with our new profile, we'll need to activate it. We do that by creating a sym-link from ```sites-available``` to ```sites-enabled```.
```shell_script
[remote] $ sudo ln -s /etc/nginx/sites-available/<PROFILENAME> /etc/nginx/sites-enabled/
```

Let's put some dummy-page into the new profile-root.

First, create the actual directory, transfer ownership to your new sudo user.
```shell_script
[remote] $ sudo mkdir /var/www/<PROFILENAME> && sudo chown <USERNAME>:<USERNAME> /var/www/<PROFILENAME>
```

Add some dummy index.html.
```shell_script
[remote] $ echo "<!DOCTYPE html><html><head><title>Hello world!</title></head><body>Hello, World!</body></html>" > /var/www/<PROFILENAME>/index.html
```

Right on. Restart nginx.
```shell_script
[remote] $ sudo systemctl reload nginx
```

This should, in principle, setup a bare-bones *hello-world site* on http://<DOMAIN> as well as on http://www.<DOMAIN>.
Sadly, we have just told cloudflare, that we would love them to proxy all the traffic to our site and upgrade and e2e encrypt *all* connections to use SSL.
Therefore, if we now point our browser to http://<DOMAIN> we get a nice cloudflare error telling us that everything worked out alright, except that our server is not setup correctly. :(

Let's fix that next.

# Setup nginx & certbot via cloudflare
## cloudflare config 
First, create a directory to hold all cloudflare configurations, I chose ```~/.config/cloudflare/```.
```shell_script
[remote] $ mkdir -p ~/.config/cloudflare && sudo chmod 0700 ~/.config/cloudflare
```
Get your global API key from the cloudflare dashboard (https://support.cloudflare.com/hc/en-us/articles/200167836-Where-do-I-find-my-Cloudflare-API-key-#12345682).

Then create a dns-config file in the cloudflare config directory (I called it ```credentials.ini```) we just created.
```shell_script
[remote] $ sudo vim ~/.config/cloudflare/credentials.ini
```

Enter the following information into this file:
```
dns_cloudflare_email   = "<YOUR_CLOUDFALRE_ACCOUNT_EMAIL>"
dns_cloudflare_api_key = "<YOUR_CLOUDFLARE_API_KEY>"
```

Now, lock down the file.
```shell_script
[remote] $ sudo chmod 0400 ~/.config/cloudflare/credentials.ini
```

## certbot config
Great. Let's install some software. We want ```certbot``` to do the heavy lifting for us, so we don't have to care about all the SSL business in the future.
```shell_script
[remote] $ sudo apt install certbot python3-certbot-nginx python3-certbot-dns-cloudflare 
```

Run certbot using ```nginx``` as *installer* and ```dns-cloudflare``` as authenticator. In other words, we ask certbot to install the certificates granted by cloudflare into nginx.
```shell_script
[remote] $ sudo certbot --installer=nginx --authenticator=dns-cloudflare
```

Certbot will ask you for an e-mail address, to which they can send you emails in case of *urgent* renewal situations and security notes.
After reading (!) and agreeing to the *Let's Encrypt terms of service* you can decide if you want to receive emails (on the email you previously entered) about news from the EFF.

Now for some important input. You should be presented with the following question next:
```
Which names would you like to activate HTTPS for?
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
1: DOMAIN 
2: www.DOMAIN
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Select the appropriate numbers separated by commas and/or spaces, or leave input
blank to select all options shown (Enter 'c' to cancel):
```
Make sure to select both (www.DOMAIN as well as DOMAIN) and continue.

Next, input the path to the cloudflare credentials INI file we created earlier (I created it in ```~/.config/cloudflare/credentials.ini```).

Next question:
```
Please choose whether or not to redirect HTTP traffic to HTTPS, removing HTTP access.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
1: No redirect - Make no further changes to the webserver configuration.
2: Redirect - Make all requests redirect to secure HTTPS access. Choose this for
new sites, or if you're confident your site works on HTTPS. You can undo this
change by editing your web server's configuration.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Select the appropriate number [1-2] then [enter] (press 'c' to cancel): 
```
Here you want to choose 2 for *Redirect*.

If everything worked out, you should be presented with two test-links in the form of ```https://www.ssllabs.com/ssltest/analyze.html?d=DOMAIN``` go to both, check that things check out.

Now it's time to point your browser to http://DOMAIN (yes http **NOT** https) to check if the automatic redirect works. If all went according to plan, you should now see your glorious *Hello, World* page but nicely secured with SSL, curtesy of cloudflare.

The curious might want to check out the nginx profile we set up a while ago.
```shell_script
[remote] $ cat /etc/nginx/sites-available/<PROFILENAME>
```

Notice the additions. ```certbot``` added SSL listeners on port 443 (for IPv4 and IPv6 respectively), linked up the certificates that were issued to our domain by cloudflare. Also, we find a newly added ```server {}``` section there. This is our automatic redirect from ```http``` to ```https```. Looks a bit ill-formatted but otherwise exactly what we wanted. Good stuff!

## automatic certification renewal
Certbot should have setup two things, when we configured it for ```nginx``` using certificates from cloudflare.

1. crontab entries in ```/etc/cron.d/certbot```
2. systemd timer called ```certbot.timer``` - to display the timer, run
    ```shell_script
    [remote] $ sudo systemctl show certbot.timer
    ```

So we should be fine.

# SSH via cloudflare
Since our domain is now proxied by cloudflare, trying to establish an SSH connection via ```ssh <USERNAME>@<DOMAIN>``` is no longer possible.

Since this 'step' is slightly more involved, I have written a script that does this for us - both on the remote machine as well as on our local machine(s).

```shell_script
[remote] web-server $ ./cloudflared_setup.sh
```
Follow the instructions.

After that script has run successfully, run **the same script** on your local machine as well.
```shell_script
[local] web-server $ ./cloudflared_setup.sh local
```

Success.
