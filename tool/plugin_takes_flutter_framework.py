"""Whether the plugin depends on FlutterFramework, in a graph written by
`swift package show-dependencies --format json`. Exits 1 when it does not.

Run by CI on the package Flutter generates for the example's plugins.
"""
import json
import sys


def packages(node):
    yield node
    for child in node.get('dependencies', []):
        yield from packages(child)


graph = json.load(open(sys.argv[1], encoding='utf-8'))
plugins = [p for p in packages(graph)
           if p.get('identity', '').startswith('universal_barcode_scanner')]
if not plugins:
    sys.exit('The plugin is not in the graph.')
for plugin in plugins:
    names = [d.get('identity') for d in plugin.get('dependencies', [])]
    if 'flutterframework' not in names:
        sys.exit(f'The plugin depends on {names}, not on FlutterFramework.')
print('The plugin depends on FlutterFramework.')
