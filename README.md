Cubietruck-Debian
=================

Scripts to create an Image of Debian for cubietruck

Created from Igor Pečovnik work at :

http://www.igorpecovnik.com/2013/12/24/cubietruck-debian-wheezy-sd-card-image/


Installation steps
------------------

```shell
sudo apt-get -y install git
cd ~
git clone https://github.com/deksan/Cubietruck-Debian
chmod +x ./Cubietruck-Debian/build.sh
cd ./Cubietruck-Debian
./build.sh
```



Todo List
------------------
- [ ] Let user param more things ( Language / Keyboard layout / Output dir / VGA-HDMI Output )
- [ ] 2gb patch for kernel

