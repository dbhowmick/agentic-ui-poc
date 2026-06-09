// `@meldui/a2ui@0.1.0` ships a broken `dist/vue/index.d.ts` that re-exports from
// a non-published `../src/vue/index` path, so `@meldui/a2ui/vue`'s symbols are
// invisible to TypeScript even though the runtime works. The same types are
// fully declared in the main entry's `dist/index.d.ts` — re-declare just the
// Vue runtime exports here against that file so consumers can import from
// `@meldui/a2ui/vue` without TS errors. Remove this shim once upstream ships
// a correct subpath .d.ts.
declare module '@meldui/a2ui/vue' {
  export {
    A2UI_CONTEXT,
    A2UISurface,
    DeferredChild,
    buildVueCatalog,
    defineVueComponent,
    meldTheme,
    meldVueCatalog,
    pendingRendererComponents,
    provideA2UI,
    toVueRef,
  } from '@meldui/a2ui'
  export type {
    A2uiActionHandler,
    A2uiContext,
    A2uiHandle,
    A2uiRenderProps,
    MeldTheme,
    ProvideA2uiOptions,
    VueComponentApi,
  } from '@meldui/a2ui'
}
