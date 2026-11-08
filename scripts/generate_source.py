#!/usr/bin/env python3
"""Generate AltStore Classic/SideStore metadata from the actual released IPA."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('ipa', type=Path)
parser.add_argument('tag')
parser.add_argument('--date', default=datetime.now(timezone.utc).isoformat())
args = parser.parse_args()
repo = 'https://github.com/nook-agent/mnn-llm-chat-builder'
raw = 'https://raw.githubusercontent.com/nook-agent/mnn-llm-chat-builder/main'
with zipfile.ZipFile(args.ipa) as archive:
    info_paths = [n for n in archive.namelist() if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
    assert len(info_paths) == 1, info_paths
    info = plistlib.loads(archive.read(info_paths[0]))
privacy = {key: value for key, value in info.items() if key.startswith('NS') and key.endswith('UsageDescription')}
version = {
    'version': info['CFBundleShortVersionString'],
    'buildVersion': info['CFBundleVersion'],
    'date': args.date,
    'localizedDescription': 'Global Hugging Face search, public MNN model downloads by URL, and folder/multi-file import through Files.',
    'downloadURL': f'{repo}/releases/download/{args.tag}/MNNLLMChat.ipa',
    'size': args.ipa.stat().st_size,
    'minOSVersion': info['MinimumOSVersion'],
}
source = {
    'name': 'Nook · MNN Chat',
    'identifier': 'io.github.nook-agent.mnn-llm-chat-builder',
    'sourceURL': f'{raw}/source.json',
    'subtitle': 'MNN Chat with Hugging Face search and model import',
    'description': 'Community build of Alibaba MNN Chat. Public MNN model downloads, Hugging Face search and Files import. Requires iOS 17 or later. For AltStore Classic and SideStore.',
    'website': repo,
    'iconURL': f'{raw}/assets/icon.png',
    'tintColor': '#3877F4',
    'apps': [{
        'name': 'MNN Chat',
        'bundleIdentifier': info['CFBundleIdentifier'],
        'developerName': 'Alibaba MNN · nook-agent build',
        'subtitle': 'Local AI · Hugging Face · Files import',
        'localizedDescription': 'Run MNN language models locally on your iPhone or iPad. Includes global Hugging Face search, public model downloads by repository/folder URL, and import of unpacked model folders or selected files. Models are downloaded separately. Supports MNN LLM exports; GGUF and safetensors need conversion. Community modified build, not an official Alibaba release.',
        'iconURL': f'{raw}/assets/icon.png',
        'tintColor': '#3877F4',
        'versions': [version],
        # Compatibility with older source parsers.
        'version': version['version'], 'versionDate': version['date'],
        'versionDescription': version['localizedDescription'],
        'downloadURL': version['downloadURL'], 'size': version['size'],
        'appPermissions': {'entitlements': [], 'privacy': privacy},
    }],
    'news': [],
}
Path('source.json').write_text(json.dumps(source, ensure_ascii=False, indent=2) + '\n')
print(f'Generated source.json: {version["version"]} ({version["buildVersion"]}), {version["size"]} bytes')
