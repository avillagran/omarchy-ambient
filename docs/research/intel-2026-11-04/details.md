# Intel: comparación TTFx y escenas ASCII

Fecha: 2026-11-04. Equipo físico: Intel Core i5-5257U, Iris 6100, pantalla 2560×1600, escala 2.

## Método

- Se ejecuta una sola variante a la vez, con orden de ida y vuelta. Dos muestras por variante y efecto; 6 s de calentamiento y 15–20 s de medida. Se enfría a ≤68 °C antes de cada muestra. Las que superan 90 °C se cortan y se identifican en los datos.
- CPU: porcentaje de un núcleo, incluye todos los procesos del grupo y CPU de hijos terminados. Terminal incluye Foot, shell y ttfx; GPU incluye productor y renderer. Hyprland se mide aparte.
- GPU: estimación de ocupación global a partir del tiempo fuera de RC6. No son watts ni autonomía. RAPL no es legible por este usuario.
- Mismo texto de branding y lienzo de 237×61 caracteres en las cinco pruebas TTFx. Foot usa fuente de 6.5 puntos para alojarlo (terminal observada: 256×66); nuestro renderer usa resolución 2 (237×61). La rasterización y la paleta no son idénticas entre terminal y capa GPU.
- Terminal120 conserva el límite de 120 fps del lanzador normal, pero fija el efecto y el lienzo. Terminal20 lo limita a 20 fps. Installed y merged usan 20 fps. El bloque a 120 fps se suspendió tras cortes térmicos en Matrix y Beams. El límite solicitado en terminal no acredita fps presentados; solo el renderer GPU emite estadísticas de cuadros.
- La terminal es una ventana fullscreen y el renderer una capa bottom: la comparación incluye estas diferencias de arquitectura. No es una prueba de píxeles iguales entre ambos productos.
- Installed es el binario ya instalado antes de este ensayo; merged es el árbol combinado de las últimas optimizaciones, construido en el Intel. No se reemplaza la instalación.

## Resultados

Medianas; CPU del programa y Hyprland se expresan por núcleo. GPU es global.

| Efecto | Variante | n | CPU % | Rango CPU % | Hyprland % | GPU fuera RC6 % | Máxima °C | Cortes térmicos |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| matrix | terminal120 | 2 | 178.43 | 177.35–179.52 | 25.98 | 41.34 | 92 | 2 |
| matrix | installed | 2 | 5.06 | 4.99–5.14 | 4.60 | 24.12 | 70 | 0 |
| matrix | merged | 2 | 4.86 | 4.75–4.98 | 4.57 | 23.83 | 68 | 0 |
| matrix | terminal20 | 2 | 123.70 | 122.08–125.31 | 22.02 | 12.60 | 70 | 0 |
| beams | terminal120 | 1 | 173.14 | 173.14–173.14 | 26.30 | 41.98 | 92 | 1 |
| beams | installed | 2 | 4.75 | 4.65–4.85 | 4.43 | 21.31 | 81 | 0 |
| beams | merged | 2 | 3.68 | 3.68–3.68 | 4.30 | 20.90 | 68 | 0 |
| beams | terminal20 | 2 | 126.10 | 124.15–128.06 | 24.36 | 12.51 | 70 | 0 |
| rings | installed | 2 | 3.38 | 3.28–3.49 | 4.35 | 19.76 | 66 | 0 |
| rings | merged | 2 | 3.07 | 2.91–3.22 | 4.46 | 20.06 | 66 | 0 |
| rings | terminal20 | 2 | 113.15 | 110.46–115.83 | 25.05 | 12.32 | 68 | 0 |
| decrypt | installed | 2 | 2.72 | 2.71–2.72 | 3.40 | 14.23 | 65 | 0 |
| decrypt | merged | 2 | 2.55 | 2.51–2.58 | 3.26 | 13.94 | 66 | 0 |
| decrypt | terminal20 | 2 | 111.40 | 109.57–113.24 | 25.57 | 12.28 | 67 | 0 |
| thunderstorm | installed | 2 | 3.13 | 3.04–3.21 | 4.38 | 19.63 | 65 | 0 |
| thunderstorm | merged | 2 | 2.97 | 2.91–3.04 | 4.46 | 19.48 | 67 | 0 |
| thunderstorm | terminal20 | 2 | 111.97 | 110.68–113.27 | 25.20 | 12.54 | 67 | 0 |
| neon-city | installed | 2 | 8.58 | 7.59–9.58 | 3.73 | 24.38 | 68 | 0 |
| neon-city | merged | 2 | 7.45 | 6.84–8.06 | 3.45 | 24.34 | 68 | 0 |
| aquarium | installed | 2 | 4.29 | 4.24–4.35 | 3.22 | 23.99 | 68 | 0 |
| aquarium | merged | 2 | 4.23 | 4.17–4.28 | 3.02 | 23.81 | 68 | 0 |
| circuit-run | installed | 2 | 8.33 | 7.92–8.75 | 3.73 | 24.47 | 69 | 0 |
| circuit-run | merged | 2 | 7.70 | 6.13–9.28 | 3.61 | 24.38 | 70 | 0 |

## Ganancia de CPU

| Efecto | Terminal20 → merged | Installed → merged |
|---|---:|---:|
| matrix | 96.1 % | 3.9 % |
| beams | 97.1 % | 22.4 % |
| rings | 97.3 % | 9.3 % |
| decrypt | 97.7 % | 6.4 % |
| thunderstorm | 97.3 % | 4.9 % |
| neon-city | — | 13.2 % |
| aquarium | — | 1.5 % |
| circuit-run | — | 7.6 % |

Una ganancia negativa significa más CPU en merged. Dos muestras cortas por variante no bastan para afirmar cambios pequeños; se muestran los rangos para reconocer solapamientos. Los efectos son aleatorios y atraviesan fases distintas.

## Archivos de evidencia

- `results.jsonl`: muestras individuales y duración efectiva.
- `*-*.log`: stderr y estadísticas del renderer.
- `bench.py`, `effect.sh`: comandos y recolector reproducibles.
- `source.patch`: cambios exactos del renderer respecto de HEAD 4d9a7fb4528a7da93b6cc0ba018be2f4ccd400aa.
- `provenance.json`: hashes de ejecutables y árbol fuente.

## Cadencia GPU observada

| Muestra merged | FPS según ventanas de estadísticas de 5 s |
|---|---:|
| matrix-merged-1 | 19.55 |
| matrix-merged-2 | 19.60 |
| beams-merged-1 | 20.20 |
| beams-merged-2 | 20.07 |
| rings-merged-1 | 20.07 |
| rings-merged-2 | 20.13 |
| decrypt-merged-1 | 15.80 |
| decrypt-merged-2 | 15.73 |
| thunderstorm-merged-1 | 20.13 |
| thunderstorm-merged-2 | 20.20 |
| aquarium-merged-1 | 20.00 |
| aquarium-merged-2 | 20.00 |
| circuit-run-merged-1 | 20.00 |
| neon-city-merged-1 | 20.00 |
| neon-city-merged-2 | 20.00 |
| circuit-run-merged-2 | 20.00 |

## Configuración cotidiana de la terminal

Foot usa la configuración de screensaver de Omarchy, fuente de 18 puntos, límite solicitado de 120 fps y canvas automático. Se fija cada efecto para medirlo. Esta tabla representa una comparación de configuraciones de uso: densidad y límite de fps distintos; no aísla por sí sola la eficiencia del motor.

| Efecto | n | Foot+TTFx CPU % | merged CPU % a 20 fps | Foot GPU fuera RC6 % | merged GPU fuera RC6 % | Fuente18 máx °C |
|---|---:|---:|---:|---:|---:|---:|
| matrix | 2 | 134.86 | 4.86 | 45.93 | 23.83 | 84 |
| rings | 2 | 135.47 | 3.07 | 47.58 | 20.06 | 82 |
| thunderstorm | 2 | 133.65 | 2.97 | 47.26 | 19.48 | 82 |

Tamaños de terminal observados (filas, columnas): 25 88.

## Estado final verificado

Intel quedó en `none`, sin renderer, TTFx, Foot ni captura de audio de las pruebas. El hash instalado sigue siendo `6f9b0f7e…`. Tras enfriar, el sensor marcó 63 °C; Hyprland quedó sin CPU detectable en una ventana de 15 s. RC6 indica GPU aproximadamente en reposo (estimación cruda −0,65 %, desfase entre contadores; no ocupación negativa física). M2 conserva `sand-clock-dunes`.
