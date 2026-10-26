# Lecciones de motores de juegos para Ambient

Investigación del 2026-10-26. Estado: diseño contrastado con código y resultados;
no nuevo candidato, benchmark, instalación ni modificación del renderer v1.
Base validada: ttfx `2307875`, documentación `eb5cd5f`. Alcance inicial Matrix,
ambos placements; no extrapolar a FS-UAE/Amiga ni a todos los efectos.

## Conclusión

La siguiente investigación útil es una representación de escena persistente y
compacta, con eventos discretos separados de la posición que se dibuja. Primero
hay que demostrar que abarata el camino actual a ~37.6 actualizaciones/s. Sólo
entonces evaluar movimiento entre actualizaciones en GPU, con latencia explícita.
Cambiar exclusivamente shaders, número de draw calls o quitar el sleep no ataca
el problema completo. Tampoco hace falta incorporar Godot/Unity como dependencia.

## Qué enseñan los engines y cómo aplica

### Simulación, representación y presentación son relojes distintos

[Fiedler](https://gafferongames.com/post/fix_your_timestep/) explica por qué ligar
simulación a la frecuencia de render cambia su comportamiento, y cómo interpolar
estados. [Godot GPUParticles2D](https://docs.godotengine.org/en/stable/classes/class_gpuparticles2d.html)
expone frecuencia fija e interpolación de movimiento a mayor refresco. Esto
sugiere conservar las decisiones discretas a su ritmo y dibujar posiciones entre
ellas; no ejecutar más veces RNG/respawn para fabricar60fps.

Advertencia local: Matrix NO tiene actualmente un reloj fijo40Hz: duerme25ms
DESPUÉS de cómputo/publicación. Pasarlo a deadlines25ms lo aceleraría. Preservar
el algoritmo por paso y RNG no prueba igual velocidad de pared. Una arquitectura
con reloj explícito necesita un contrato nuevo de velocidad antes de activarse.
Para investigación inicial se usan timestamps reales grabados, sin retimarlos.

### Datos persistentes, instancias compactas y separación de responsabilidades

[Unity Entities](https://docs.unity3d.com/Packages/com.unity.entities@1.0/manual/concepts-archetypes.html)
agrupa componentes en arrays compactos por tipo. La lección aplicable es evitar
transportar/reinterpretar campos que el siguiente consumidor no necesita, no
instalar un ECS. [Unity Particle Instancing](https://docs.unity3d.com/6000.0/Documentation/Manual/PartSysInstancing.html)
usa buffers de instancias; sus requisitos de shader no se trasladan literalmente
a nuestro GLES. En [Godot particles.glsl](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/shaders/particles.glsl)
el estado de partículas y parámetros temporales están separados en buffers.
[particles_copy.glsl](https://raw.githubusercontent.com/godotengine/godot/master/servers/rendering/renderer_rd/shaders/particles_copy.glsl)
consume datos de partículas y escribe datos de instancias: una separación
concreta entre simulación y representación. Son ejemplos de arquitectura,
no prueba de ahorro sobre Iris ni instrucciones para copiar sus shaders Vulkan.

Propuesta local: persistir dos estados de representación ya resueltos y sus
identidades/epochs; actualizar atributos discretos una vez por publicación,
y reutilizarlos entre refrescos. El vertex shader puede interpolar posición
con un parámetro temporal pequeño, sin reconstruir listas/VBO en CPU por cada
presentación. Mantener samplers normalizados y exactitud de endpoints de v1.
GPU no significa gratis: fetches/varyings/overdraw pueden superar el ahorroCPU.

### Batching es un intercambio, no una meta

[Godot GPU optimization](https://docs.godotengine.org/en/latest/tutorials/performance/gpu_optimization.html)
explica el coste de llamadas/estado y la pérdida de granularidad de culling al
agrupar. Su [análisis de CPU rendering](https://godotengine.org/article/rendering-cpu-optimizations/)
remarca que optimizar un procesador puede empeorar el otro. Nuestros R6 y R22 ya
lo ilustran: menos llamadas no acreditaron ahorro global; R13 redujo trabajo
geométrico pero añadió listas/limpiezaCPU. No repetir esas rondas como novedades.

Cualquier representación nueva conservará cobertura y borrado correctos. Si se
mueven glifos, el daño incluye posición anterior+nueva y el historial de buffer
age, también fuera de la celda original. No usar full-surface por comodidad ni
omitir borrado. Si la unión termina casi llena, registrar ese coste real.

### Pacing y cola corta, sin confundir callback con instante físico

[Android Frame Pacing](https://developer.android.com/games/sdk/frame-pacing)
usa coordinación temporal y sincronización para evitar llenar la cola y añadir
latencia. Es un patrón, no una biblioteca aplicable directamente a Wayland.
Nuestro equivalente debe usar callbacks/feedback reales, relojes compatibles y
colas acotadas. No quitar frame_pending para enviar lo más rápido posible.
[Khronos](https://wikis.khronos.org/opengl/Performance) recuerda que OpenGL es
asíncrono: duración CPU de submit no es tiempo GPU. Ya disponemos de queries
optativas diferidas; conservarlas separadas de las corridas de recursos.

## Contraste con implementación real

En `bin/ttfx-bg-rs/src/main.rs` de2307875:

- `fx_matrix_with_rng` (~4524): arrays de cabezas/velocidad/trails, paleta por
  nacimiento; elige símbolos aleatorios para cada glifo visible CADA paso.
  Borra, pinta, avanza, publica y finalmente duerme. Ésta es la ruta nativa usada;
  `ttfx-src/src/effects/matrix.rs` es otro catálogo y no explica esta medición.
- `Screen::present` (~2497): recorre ocupados, resuelve SGR, reconstruye
  `Vec<DirectCell>`, publica bajo mutex y notifica generación.
- `asm_direct_bridge.rs::DirectCell`: coordenadas usize, char, colores,
  background y atributos; tamaño observado40B. Es sparse por ocupados, NO una
  matriz densa. No asumir que reducir tamaño reduce tiempo proporcionalmente.
- `gpu_grid.rs::fill/damage_tiles/draw`: resuelve atlas, arma planos, compara
  daño y dibuja. V1 ya cachea slots y restringe quads porclip.
- `wl_layer.rs` (~480–534): consume generación y somete sólo dirty con callback
  disponible. Evidencia anterior localizó ~37.6 ya en productor, no descartes.

R15 ya intentó separación temporal: fuente5abc93c, ledger
`docs/performance-rounds-9-28.md` del worktree perf-ambient-frame-budget.
Piloto frío logró60feedback/s, pero NO ABBA: latencia geometría p50~50/p99~61ms,
CPUhilo productor1.505→2.582ms, intervalo26.737→27.818ms; coste diagnóstico alto.
Copiaba snapshots, reconstruía sprites y redibujaba superficie completa. No se
puede adjudicar causalidad a una sola etapa con esos datos. La propuesta nueva
sólo merece ensayo si elimina trabajo material de esa arquitectura y controla
su latencia; no basta rebautizarla.

## Orden de pruebas propuesto

1. **Auditoría de representación sobre trazas reales.** Medir bytes y CPU por
   publicación/consumo/fill, allocations y transporte; separar campos calientes
   y fríos. Contrastar representación compacta sin cambiar simulación, sleep,
   RNG ni ABI compartido de ASM. No construir un diff de miles de celdas por
   reflejo: investigación previa halló apenas~1.4% idénticas en igual posición.
   El objetivo es menos conversiones/copias, no prometer pocos eventos.
2. **Escena persistente exacta, al ritmo actual.** Prototipo aislado con buffers
   reutilizables, atlas con generación y fallback explícito. Originalv1 vsnuevo,
   endpoints RGBA y orden completos, RNG idéntico, respawn/residentes/erase,
   Unicode/styles, palette-born, resize y buffer-age. Registrar CPU/GPU/bytes
   incluso si pierde; si no abarata, no añadir interpolación encima.
3. **Muestreo visual en GPU, sólo después.** Dos endpoints y metadatos se
   actualizan al cambiar publicación; entre ellos sólo tiempo/posición. Símbolo,
   color y estilo son eventos discretos; no crossfade de grillas. Persistentes
   permanecen fijos hasta su erase/overwrite real. Cortes de epoch no interpolan.
   No afirmar que un head porcolumna describe el estado completo. Hold causal
   sin extrapolación; latencia solicitada y efectiva separadas. El renderer
   continúa atendiendo input/stop sin esperar un tick de simulación.
4. **Validación física antes de seleccionar default.** Gates Iris exactos de
   endpoints, oráculo de geometría intermedia y vídeo de movimiento; reloj
   virtual con jitter/fases y timestamps reales; ABBA20→45 si prometedor, ambos
   placements. Medir latencia física, holds, fuentes/presentaciones/poses nuevas,
   CPU/RC6/temperatura, RSS y costesGPU por separado. Mouse/tecla/clic/scroll,
   lock/resize, occlusion y restauración forman parte del contrato. Comparar
   contra v1 y controlar velocidad, no contra la referencia antigua para
   atribuirle mejoras que v1 ya tiene.

## Presupuesto y límites de viabilidad

59.972/37.6 =1.595: dibujar en cada refresco añade~59.5% de presentaciones.
En una partida estrictamente proporcional a cuadros, el coste unitario debe
caer al37.6/59.972=62.70% (ahorro37.30%) sólo para empatar. Esto NO convierte RC6
en tiempoGPU ni predice consumo total: hay costes por tick, porframe, fijos y
compositor. El ahorro~5–6%RC6 de v1 no demuestra margen suficiente para60.

El panel medido es~60Hz: renderizar internamente120fps no produce120 imágenes
visibles ahí y puede gastar más. Repetir buffers tampoco prueba movimiento nuevo.
Migrar a Vulkan, simular RNG en GPU, rebajar resolución o insertar sleeps menores
no son próximos pasos justificados. Una rutaGPUprocedural nueva podría ser otro
producto visual, no equivalencia automática al efecto existente.

La v1 permanece congelada. Esta investigación no cambia default ni instala nada.
La hipótesis prioritaria es **abaratar la representación persistente antes de
pagar más refrescos**; beneficio y viabilidad de60 siguen pendientes de prueba.
