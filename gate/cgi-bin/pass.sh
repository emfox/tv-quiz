#!/system/bin/sh
date +%s > /data/local/tmp/tvquiz/pass.stamp
chmod 644 /data/local/tmp/tvquiz/pass.stamp
echo "Content-Type: text/plain"
echo ""
echo ok
