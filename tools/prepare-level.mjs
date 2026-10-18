// Turns a web-build level (meshopt-compressed, quantized) into a plain GLB that Godot imports.
//   node tools/prepare-level.mjs <in.glb> <out.glb>
// Needs @gltf-transform/core, /extensions, /functions and meshoptimizer (see package.json).
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS, EXTMeshoptCompression } from '@gltf-transform/extensions';
import { dequantize } from '@gltf-transform/functions';
import { MeshoptDecoder } from 'meshoptimizer';

const [input, output] = process.argv.slice(2);
if (!input || !output) {
  console.error('usage: node tools/prepare-level.mjs <in.glb> <out.glb>');
  process.exit(1);
}

await MeshoptDecoder.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ 'meshopt.decoder': MeshoptDecoder });
const document = await io.read(input);
document.getRoot().listExtensionsUsed().find((e) => e.extensionName === EXTMeshoptCompression.EXTENSION_NAME)?.dispose();
await document.transform(dequantize());
await io.write(output, document);

const root = document.getRoot();
console.log(`${output}: ${root.listNodes().length} nodes, ${root.listMeshes().length} meshes, extensions: ${root.listExtensionsUsed().map((e) => e.extensionName).join(', ') || 'none'}`);
