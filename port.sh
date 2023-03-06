# 檢查 root 權限
if [ `id -u` -ne 0 ]; then
   echo "這個 script 需要 root 權限!"
   exit 1
fi

# 把 port forwarding 定義成函數
remap_tcp_port() {
   iptables -t nat -A PREROUTING -p tcp --dport $2 -j REDIRECT --to-ports $1
   iptables -t nat -A OUTPUT -p tcp -d localhost --dport $2 -j REDIRECT --to-ports $1
}

# 允許 port forwarding
sysctl -w net.ipv4.ip_forward=1

# 設定要轉送的 port (呼叫上面定義的函數)
# a redirect to b
remap_tcp_port 8000 30000
