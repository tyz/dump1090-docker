# this example assumes you have 1 node, you'll to add a nodeSelector to force
# it to the node that has the RTL-SDR attached
#
# usage: bash k8s-deployment.yaml.sh | kubectl apply -f -

NAMESPACE=ads-b
SERVERNAME=ads-b.mydomain.com

cat <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: readsb-${NAMESPACE}-config
  namespace: ${NAMESPACE}
data:
  default.conf: |-
    server {
        listen 8080;
        server_name ${SERVERNAME};

        root /usr/share/nginx/html;
        index index.html;

        location /upintheair.json {
            root /usr/share/nginx/html/data;
            add_header Cache-Control "public, max-age=86400";
            gzip on;
        }

        location /globe_history/ {
            root /usr/share/nginx/html/data;
            gzip off;
            add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
            add_header Access-Control-Allow-Origin "*";
            add_header Content-Encoding "gzip";
        }

        # Readsb Extended API
        location /re-api/ {
            proxy_pass http://127.0.0.1:30154/re-api/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            add_header Access-Control-Allow-Origin "*";
        }

        # "Live" data: NO caching
        location /data/ {
            root /usr/share/nginx/html;
            add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
            add_header Access-Control-Allow-Origin "*";
            expires off;
        }

        # Traces, compressed, but with extension .json
        location /data/traces/ {
            root /usr/share/nginx/html;
            gzip off;
            add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
            add_header Access-Control-Allow-Origin "*";
            add_header Content-Encoding "gzip";
        }

        # History (Chunks)
        location /chunks/ {
            root /usr/share/nginx/html/data;
            gzip_static off;
            location ~ chunk_.*\.gz\$ {
                gzip off;
                add_header Cache-Control "public, max-age=86400";
                add_header Content-Encoding "gzip";
                add_header Content-Type "application/json";
            }
            location ~ current_.*\.gz\$ {
                gzip off;
                add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
                add_header Content-Type "application/json";
                add_header Content-Encoding "gzip";
                add_header Access-Control-Allow-Origin "*";
            }
            location ~ .*\.json\$ {
                gzip on;
                add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
                add_header Content-Type "application/json";
                add_header Access-Control-Allow-Origin "*";
            }
        }

        # Airplane DB (db2): Cache for a long time
        location /db2/ {
            root /usr/share/nginx/html;
            add_header Access-Control-Allow-Origin "*";
            add_header Cache-Control "public, max-age=86400";
        }

        # Static UI stuff
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
            expires 7d;
            add_header Cache-Control "public, no-transform";
        }

        # The base
        location / {
            try_files \$uri \$uri/ =404;
            # index.html zelf liever niet te lang cachen voor updates
            add_header Cache-Control "no-cache";
        }
    }
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: readsb-${NAMESPACE}-pv-persistent
  namespace: ${NAMESPACE}
spec:
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: 10Gi
  hostPath:
    path: /srv/readsb/persistent
  storageClassName: sdcard
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: readsb-${NAMESPACE}-pv-volatile
  namespace: ${NAMESPACE}
spec:
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: 1Gi
  hostPath:
    path: /srv/readsb/volatile
  storageClassName: tmpfs
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: readsb-${NAMESPACE}-persistent-pv-claim
  namespace: ${NAMESPACE}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: sdcard
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: readsb-${NAMESPACE}-volatile-pv-claim
  namespace: ${NAMESPACE}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
  storageClassName: tmpfs
---
apiVersion: v1
kind: Service
metadata:
  name: readsb-${NAMESPACE}
  namespace: ${NAMESPACE}
spec:
  ports:
  - name: re-api
    port: 30154
    protocol: TCP
    targetPort: 30154
  - name: ui
    port: 8080
    protocol: TCP
    targetPort: 8080
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: readsb-${NAMESPACE}
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/instance: readsb
      app.kubernetes.io/name: ${NAMESPACE}
  template:
    metadata:
      labels:
        app.kubernetes.io/instance: readsb
        app.kubernetes.io/name: ${NAMESPACE}
    spec:
      containers:
      - env:
        - name: CHUNK_SIZE
          value: "60"
        - name: GZIP_LVL
          value: "6"
        - name: HISTORY_SIZE
          value: "1000"
        - name: INTERVAL
          value: "8"
        - name: SRC_DIR
          value: /data
        - name: TZ
          value: Europe/Amsterdam
        image: ghcr.io/tyz/adsb-chunks:latest
        imagePullPolicy: IfNotPresent
        name: adsb-chunks
        volumeMounts:
        - mountPath: /data
          name: data
          readOnly: false
      - args:
        - --device-type
        - rtlsdr
        - --ppm
        - "0"
        - --gain
        - auto-verbose
        - --lat
        - "52.392629"
        - --lon
        - "4.881165"
        - --quiet
        - --modeac
        - --heatmap
        - "30"
        - --write-json
        - /var/ads-b/data
        - --write-json-binCraft-only
        - "1"
        - --write-globe-history
        - /var/ads-b/data/globe_history
        - --json-trace-interval
        - "0.1"
        - --db-file
        - /var/ads-b/tar1090-db/aircraft.csv.gz
        - --net
        - --net-api-port
        - "30154"
        env:
        - name: ENABLE_BIAS_T
          value: "false"
        - name: INSTALL_AIRCRAFT_DB
          value: "true"
        - name: TZ
          value: Europe/Amsterdam
        image: ghcr.io/tyz/adsb-readsb:latest
        imagePullPolicy: IfNotPresent
        name: adsb-readsb
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /dev/bus/usb
          name: dev-bus-usb
          readOnly: true
        - mountPath: /var/ads-b/data
          name: data
          readOnly: false
        - mountPath: /var/ads-b/tar1090-db
          name: aircraft-db
          readOnly: false
      - env:
        - name: TZ
          value: Europe/Amsterdam
        image: ghcr.io/tyz/adsb-tar1090:latest
        imagePullPolicy: IfNotPresent
        name: adsb-tar1090
        ports:
        - containerPort: 30005
          name: beast
          protocol: TCP
        - containerPort: 30002
          name: raw
          protocol: TCP
        - containerPort: 30154
          name: re-api
          protocol: TCP
        - containerPort: 30003
          name: sbs
          protocol: TCP
        - containerPort: 8080
          name: ui
          protocol: TCP
        volumeMounts:
        - mountPath: /usr/share/nginx/html/data
          name: data
          readOnly: true
        - mountPath: /etc/nginx/conf.d
          name: nginx-config
          readOnly: true
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: readsb-${NAMESPACE}-volatile-pv-claim
      - name: aircraft-db
        persistentVolumeClaim:
          claimName: readsb-${NAMESPACE}-persistent-pv-claim
      - hostPath:
          path: /dev/bus/usb
        name: dev-bus-usb
      - configMap:
          name: readsb-${NAMESPACE}-config
        name: nginx-config
EOF
