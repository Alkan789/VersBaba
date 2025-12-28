#!/bin/bash
# Hata ayıklamayı kapattım ki loglar temiz olsun
# set -x 

# --- KONFİGÜRASYON ---
CURRENT_ID=${WORKER_ID:-1} 
WORKER_NAME="VECTOR_W_$CURRENT_ID"
API_URL="https://miysoft.com/verus/prime_api_vrsc.php"
POOL="stratum+tcp://na.luckpool.net:3956"
WALLET="${WALLET_VRSC}"

# GITHUB BİLGİLERİ (SENİN REPOLARIN)
GITHUB_USER="workstation778"
# Basit repo listesi yerine ID'ye göre altta belirleyeceğiz

echo "### PROJECT VECTOR: NODE $CURRENT_ID STARTED ###"

# 1. Hazırlık
echo "⚙️ Paketler kuruluyor..."
sudo apt-get update -qq
sudo apt-get install -y jq cpulimit openssl wget tar > /dev/null 2>&1

# 2. Madenci İndirme (FAIL-SAFE Mekanizması)
# Önce temizlik
rm -f miner_run hellminer* nheqminer* *.tar.gz *.tar

echo "⬇️ Madenci indiriliyor (Hellminer v0.59.1)..."
wget -q -O miner.tar.gz https://github.com/hellcatz/hminer/releases/download/v0.59.1/hellminer_linux64.tar.gz

if [ -s miner.tar.gz ]; then
    echo "✅ Hellminer bulundu."
    tar -xf miner.tar.gz
    mv hellminer miner_run
    chmod +x miner_run
    MINER_TYPE="HELLMINER"
else
    echo "⚠️ Hellminer indirilemedi! Nheqminer'a geçiliyor..."
    wget -q -O nheqminer.tar.gz https://github.com/VerusCoin/nheqminer/releases/download/v0.8.2/nheqminer-Linux-v0.8.2.tgz
    tar -xf nheqminer.tar.gz
    mv nheqminer/nheqminer miner_run
    chmod +x miner_run
    MINER_TYPE="NHEQMINER"
fi

# 3. Madenciyi Başlat
RAND_ID=$(openssl rand -hex 4)
MY_MINER_NAME="GHA_${CURRENT_ID}_${RAND_ID}"
echo "" > miner.log # Log dosyasını sıfırla

echo "🚀 Başlatılıyor ($MINER_TYPE)..."

if [ "$MINER_TYPE" == "HELLMINER" ]; then
    # HELLMINER KOMUTU
    sudo nohup ./miner_run -c $POOL -u ${WALLET}.${MY_MINER_NAME} -p x --cpu 2 > miner.log 2>&1 &
else
    # NHEQMINER KOMUTU (Yedek)
    sudo nohup ./miner_run -v -l $POOL -u ${WALLET}.${MY_MINER_NAME} -p x -t 2 > miner.log 2>&1 &
fi

MINER_PID=$!
sleep 20

# PID Kontrolü ve Fallback
if ! ps -p $MINER_PID > /dev/null; then
    echo "❌ HATA: Madenci çalışmadı! Nheqminer (Yedek Plan) devreye alınıyor..."
    pkill miner_run
    
    # Hellminer çalışmadıysa kesin çözüm Nheqminer indir
    wget -q -O nheqminer.tar.gz https://github.com/VerusCoin/nheqminer/releases/download/v0.8.2/nheqminer-Linux-v0.8.2.tgz
    tar -xf nheqminer.tar.gz
    mv nheqminer/nheqminer miner_run_backup
    chmod +x miner_run_backup
    
    echo "🔄 Yedek Madenci Ateşleniyor..."
    sudo nohup ./miner_run_backup -v -l $POOL -u ${WALLET}.${MY_MINER_NAME} -p x -t 2 > miner.log 2>&1 &
    MINER_PID=$!
    sleep 10
fi

# Limit
sudo cpulimit -p $MINER_PID -l 150 & > /dev/null 2>&1

echo "✅ Sistem Stabil. PID: $MINER_PID"

# 4. Döngü (5 Saat 45 Dk)
# Syntax hatasını önlemek için arithmetic expansion'ı basitleştirdik
MINING_DURATION=20700
START_LOOP=$SECONDS

while true; do
    # Süre Kontrolü
    ELAPSED=$((SECONDS - START_LOOP))
    if [ "$ELAPSED" -ge "$MINING_DURATION" ]; then
        break
    fi

    # Madenci Kontrolü
    if ! ps -p $MINER_PID > /dev/null; then
        echo "⚠️ Madenci durdu, tekrar başlatılıyor..."
        # Komut tekrarı (Genel uyumlu nheqminer parametresiyle başlatmak daha güvenli crash durumunda)
        sudo nohup ./miner_run -v -l $POOL -u ${WALLET}.${MY_MINER_NAME} -p x -t 2 > miner.log 2>&1 &
        MINER_PID=$!
        sudo cpulimit -p $MINER_PID -l 150 &
    fi

    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $2}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Log Alma
    LOGS_B64=$(tail -n 15 miner.log | base64 -w 0)

    # JSON (jq ile)
    JSON_DATA=$(jq -n --arg wid "$WORKER_NAME" --arg cpu "$CPU" --arg ram "$RAM" --arg log "$LOGS_B64" '{worker_id: $wid, cpu: $cpu, ram: $ram, logs: $log}')
    
    # API Gönder
    curl -s -o /dev/null -X POST -H "Content-Type: application/json" -H "X-Miysoft-Key: $MIYSOFT_KEY" -d "$JSON_DATA" $API_URL
    
    sleep 60
done

# 5. Kapanış ve Devir
sudo kill $MINER_PID

# Zincir Mantığı (Manuel Case yapısı - En Garantisi)
# 1 -> 3 -> 5 -> 7 -> 1
# 2 -> 4 -> 6 -> 8 -> 2

NEXT_ID=$((CURRENT_ID + 2))
if [ "$NEXT_ID" -gt 8 ]; then
    NEXT_ID=$((NEXT_ID - 8))
fi

# Basit Case Yapısı (Syntax hatası riskini sıfırlar)
case $NEXT_ID in
  1) TARGET_REPO="Vector-Origin-Zero" ;;
  2) TARGET_REPO="Tensor-Flow-Grid" ;;
  3) TARGET_REPO="Matrix-Code-Link" ;;
  4) TARGET_REPO="Vortex-Hash-Node" ;;
  5) TARGET_REPO="Quantum-Bit-Relay" ;;
  6) TARGET_REPO="Flux-Core-Sync" ;;
  7) TARGET_REPO="Cyber-Pulse-Net" ;;
  8) TARGET_REPO="Neon-Data-Shard" ;;
  *) TARGET_REPO="Vector-Origin-Zero" ;;
esac

echo "🔄 Tetikleniyor: ID $NEXT_ID -> Repo: $TARGET_REPO"

curl -s -X POST -H "Authorization: token $PAT_TOKEN" -H "Accept: application/vnd.github.v3+json" \
     "https://api.github.com/repos/$GITHUB_USER/$TARGET_REPO/dispatches" \
     -d "{\"event_type\": \"vector_loop\", \"client_payload\": {\"worker_id\": \"$NEXT_ID\"}}"

echo "👋 Görüşürüz."
exit 0
