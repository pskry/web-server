# Setup a decent web-server on the internets
This is what I (personally) do right after (re-) deploying a new debian-based server somewhere on the internets (be it bare-metal, some cheap VPS or similar).

## Lock down SSH
* Before doing anything, let's create a ssh-key-pair if you haven't got one already
  ```shell_script
  [local] $ ssh-keygen -b 4096 -t rsa
  ```
  Remember the passphrase well, remember the file-name you saved it as well.

* Now, let's login to our newly installed debian remote.
  ```shell_script
  [local] $ ssh root@<SERVER-IP>
  ```

* On the remote-host, create a new sudo-user.
  ```shell_script
  [remote] $ useradd -m -G sudo -s /bin/bash <USERNAME>
  ```
  Assign a password
  ```shell_script
  [remote] $ passwd <USERNAME>
  ```

  Logout
  ```shell_script
  [remote] $ exit
  ```

* Copy RSA key from local to remote
  ```shell_script
  [local] $ ssh-copy-id -i ~/.ssh/<RSA_KEY>.pub <USERNAME>@<SERVER-IP>
  ```

* Lock down sshd
  The following script revokes the possibility to login with credientials, denies login as root and disables PAM authentication.
  ```shell_script
  [remote] $ sh web-server/lock-ssh.sh
  ```

  Now, restart sshd
  ```shell_script
  [remote] $ sudo systemctl restart sshd
  ```
