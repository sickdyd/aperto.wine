/// <reference types="nativewind/types" />

// The root layout imports global.css purely for its side effect — Metro hands
// it to NativeWind, nothing consumes a value. TypeScript 6 rejects a
// side-effect import with no declaration, so declare the shape here.
declare module "*.css" {}
