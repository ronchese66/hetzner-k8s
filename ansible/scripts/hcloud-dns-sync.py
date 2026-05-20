import os
import time
import logging
import requests
from dotenv import load_dotenv

load_dotenv('/etc/hcloud.env')

HCLOUD_TOKEN = os.getenv('HCLOUD_TOKEN')
HOSTS_FILE = '/etc/hosts'
SYNC_INTERVAL = 60
HCLOUD_API = 'https://api.hetzner.cloud/v1'

MARKER_START = '# hcloud-dns-sync start'
MARKER_END = '# hcloud-dns-sync end'

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    handlers=[logging.StreamHandler()]
)

log = logging.getLogger(__name__)


def get_servers():
    headers = {'Authorization': f'Bearer {HCLOUD_TOKEN}'}
    response = requests.get(f'{HCLOUD_API}/servers', headers=headers, timeout=10)
    response.raise_for_status()
    return response.json().get('servers', [])


def build_hosts_entries(servers):
    entries = []
    cp_count = 0
    worker_count = 0

    for server in servers:
        labels = server.get('labels', {})
        node_type = labels.get('nodeType')
        private_networks = server.get('private_net', [])

        if not private_networks:
            continue

        ip = private_networks[0].get('ip')
        if not ip:
            continue

        if node_type == 'controlPlane':
            cp_count += 1
            if cp_count == 1:
                hostname = 'cp-main.k8s.internal'
            else:
                hostname = f'cp-{cp_count}.k8s.internal'
        elif node_type == 'worker':
            worker_count += 1
            hostname = f'worker-{worker_count}.k8s.internal'
        elif node_type == 'bastion':
            hostname = 'bastion.k8s.internal'
        else:
            server_id = server.get('id')
            hostname = f'node-{server_id}.k8s.internal'

        entries.append(f'{ip}\t{hostname}')

    return entries


def read_hosts():
    with open(HOSTS_FILE, 'r') as f:
        return f.read()


def write_hosts(content):
    with open(HOSTS_FILE, 'w') as f:
        f.write(content)


def update_hosts(entries):
    current = read_hosts()

    if MARKER_START in current:
        before = current[:current.index(MARKER_START)]
        after = current[current.index(MARKER_END) + len(MARKER_END):]
    else:
        before = current
        after = ''

    block = '\n'.join([MARKER_START] + entries + [MARKER_END])
    new_content = before.rstrip('\n') + '\n' + block + '\n' + after.lstrip('\n')

    if new_content != current:
        write_hosts(new_content)
        log.info(f'Updated /etc/hosts with {len(entries)} entries')
    else:
        log.debug('No changes to /etc/hosts')


def main():
    if not HCLOUD_TOKEN:
        log.error('HCLOUD_TOKEN is not set')
        raise SystemExit(1)

    log.info('Starting hcloud DNS sync daemon')

    while True:
        try:
            servers = get_servers()
            entries = build_hosts_entries(servers)
            update_hosts(entries)
        except requests.RequestException as e:
            log.error(f'Hetzner API error: {e}')
        except Exception as e:
            log.error(f'Unexpected error: {e}')

        time.sleep(SYNC_INTERVAL)


if __name__ == '__main__':
    main()