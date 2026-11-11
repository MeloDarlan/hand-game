# hand game — tower defense

Prototype 3D isométrico em **Godot 4.7** onde a **mão gigante original** do
hand-game posiciona torres para defender o núcleo de ondas de inimigos.

A mão mantém o visual/comportamento do projeto original, agora com a **palma
para a câmera em 3/4 isométrico**: braço diagonal saindo para o canto inferior
direito, com o fim do antebraço em fade para o corte sumir no canto. CATCH/IDLE,
jelly e física de grab/drop continuam. Ela flutua na frente do tabuleiro
isométrico e carrega a peça **pendurada pela pinça do topo**, com o CATCH
fechando em volta da cabeça da torre. O pé da peça fica no tile sob o cursor.

Um **outline de oclusão** contorna só a parte do topo que está junto da mão; o
corpo pendurado continua visível sem contorno. O **indicador ciano** aparece
quando a mão está vazia (região do GrabArea/pick); com uma peça na mão, fica só
o indicador verde/vermelho do encaixe no pé dela. A peça balança visualmente
quando a mão se move (mola/inércia), mas o alvo e os indicadores ficam parados.
Depois de encaixar, a mão recua um pouco para revelar a torre e volta a seguir
o cursor no próximo movimento do mouse.

![Godot](https://img.shields.io/badge/Godot-4.7-478CBF?logo=godotengine&logoColor=white)
![Renderer](https://img.shields.io/badge/Renderer-Forward%2B-478CBF)
![Physics](https://img.shields.io/badge/Physics-Jolt%20Physics-478CBF)
![License](https://img.shields.io/badge/License-MIT-green)

## Fluxo (MVP)

- **BUILD**: escolher uma torre e posicionar com a mão.
- **WAVE**: iniciar a onda; as torres miram e atiram sozinhas.
- Limpar as 3 ondas = vitória. Perder 10 vidas = derrota.
- Tema provisório com primitivas; torres, inimigos e ondas são data-driven
  (`resources/`), prontos para trocar a arte.

| Torre | Custo | Perfil |
| --- | --- | --- |
| Canhão | 30 | Dano alto, cadência lenta |
| Rápida | 20 | Cadência alta, alcance curto |
| Gelo | 25 | Dano baixo + slow |

Inimigos: **Corredor** (rápido/frágil) e **Bruto** (lento/resistente).

## Controles

| Ação | Comando |
| --- | --- |
| Mover a mão / cursor | Mouse |
| Pegar / interagir com a peça | Clique esquerdo |
| Soltar e encaixar no tile | Clique esquerdo (press + release) |
| Escolher torre | Clique na toolbar |
| Ciclar torres | Scroll do mouse ou `1`/`2`/`3`/`4` |
| Alternar FOLLOW_MOUSE / FIXED_ARM | `M` |
| Cancelar / devolver torre | Clique direito, `Esc` ou clicar de novo no botão selecionado |
| Iniciar onda | `Espaço` ou botão "Iniciar onda" |
| Reiniciar a fase | `R` (a qualquer momento) ou botão do overlay no fim de jogo |
| +100 créditos (debug) | `F2` |

Soltar em tile inválido (caminho, ocupado ou fora do tabuleiro) não solta a
peça: a mão continua segurando. O **anel verde/vermelho** ao redor da peça
mostra se o tile é válido — útil porque a mão cobre parte do tabuleiro.

## Como rodar

1. Instale o [Godot 4.7](https://godotengine.org/download) (versão standard, não
   precisa do .NET).
2. Clone o repositório:
   ```bash
   git clone https://github.com/MeloDarlan/hand-game.git
   ```
3. Abra o Godot, clique em **Import**, selecione o arquivo `project.godot` desta
   pasta.
4. Pressione **F5** para jogar.

Pela linha de comando (Windows):

```powershell
& 'C:\caminho\para\Godot_v4.7-stable_win64.exe' --path 'D:\hand-game'
```

## Estrutura do projeto

```text
scenes/ui/main_menu.tscn         cena inicial simples (Jogar / Sair)
scenes/main.tscn                 cena principal de gameplay
scenes/hand_player.tscn          mão: PalmPivot, HoldPoint, GrabArea, ArmJelly
scenes/ui/hud.tscn               top bar, toolbar e overlay de fim de jogo
scripts/ui/main_menu.gd          montagem da tela inicial
scripts/audio/audio_manager.gd   autoload de efeitos pontuais de combate e vitória
scripts/camera_iso.gd            câmera isométrica ortográfica
scripts/board.gd                 grade, caminho, ocupação, mapa simples, highlight e range ring
scripts/hand_controller.gd       mão: mouse, pose, CATCH, grab e release_guard
scripts/build/build_controller.gd  toolbar <-> mão <-> board, créditos, encaixe
scripts/game/game_manager.gd     estado, créditos, vidas, vitória/derrota
scripts/enemies/                 Enemy e WaveManager
scripts/towers/                  TowerPiece, Projectile e OcclusionOutline
scripts/ui/hud.gd                HUD/toolbar
scripts/data/                    Resources de balanceamento
resources/                       torres, inimigos e ondas (.tres)
occlusion_outline.gdshader       outline 2D das máscaras mão/peça
assets/hand-game.glb             mão + CATCH/IDLE
assets/oleos.glb                 modelo do Olho Laser (reutiliza o olho verde original)
assets/maps/arena_prototipo.glb   mapa 3D de protótipo, com cores chapadas e sem texturas
assets/maps/preview_arena_prototipo.png prévia superior do mapa
assets/audio/sfx/               efeitos curtos de tiro, laser, morte e vitória
tools/generate_map_assets.py      gerador do GLB/preview (Python + trimesh + numpy + matplotlib)
tools/generate_audio_assets.py    gerador dos WAVs de efeito
docs/                            notas de alterações, áudio/torre e correção do mapa cinza
```

`project.godot` aponta `run/main_scene` para o menu e registra `AudioManager`
na seção `[autoload]`. O botão JOGAR troca para `scenes/main.tscn`.

As cenas de teste originais continuam em `scenes/`. O modelo `oleos.glb`, antes usado por `scenes/eye.tscn`, agora também é reutilizado como visual da torre especial Olho Laser.

## Ajustes rápidos (tuning)

| O que | Onde |
| --- | --- |
| Onde a mão pinça a peça (altura no corpo) | `grip_height` em `resources/towers/*.tres` (novas peças) ou no `TowerPiece` da peça segurada no Remote |
| Onde a pinça fica na palma | `pinch_offset` no `HandPlayer` (o GrabArea acompanha) |
| Raio do GrabArea (pick) | `grab_radius` no `HandPlayer` (efetivo = raio × `hand_scale`) |
| Cor do indicador da mão | `hand_preview_color` / `hand_ring_color` no `Board` |
| Tamanho da mão | `hand_scale` no `HandPlayer` |
| Ângulo/pose do braço | `depth_yaw_degrees`, `screen_roll_degrees`, `depth_pitch_degrees` |
| Giro da peça na mão | `held_yaw_degrees` (yaw efetivo = depth_yaw + held_yaw) |
| Fade do antebraço | `forearm_fade_start` / `forearm_fade_strength` no `ArmJelly` |
| Swing da peça carregada | `motion_*` no `TowerPiece` (Remote da peça segurada) |
| Cor/espessura do outline | `outline_color` / `outline_size` no `OcclusionOutline` |
| Volume dos SFX / vozes | `sfx_volume` / `sfx_voice_count` no autoload `AudioManager` |
| Antecipação do Olho Laser | `anticipation_enabled`, `anticipation_duration`, `anticipation_squash`, `anticipation_stretch` em `resources/towers/eye_laser.tres` |

Os exports do `HandPlayer` e do `ArmJelly`/`OcclusionOutline` aplicam na hora
(setters + `apply_pose`); o `pinch_offset` sobrescreve o Transform do HoldPoint
na cena. O anel de validade acompanha o pé da peça.

## Pós-MVP

Tema e arte final, VFX adicionais, upgrades e venda de torres, mais torres/inimigos,
mapas com caminhos diferentes e ondas infinitas. O próximo passo de feel é
ajustar o swing da peça (`motion_*`) e, se quiser, adicionar reação no eixo de
profundidade. Se a escala da mão incomodar, ajustar `hand_scale` e o fade do
antebraço para reduzir a mão sem expor o corte. Detalhes em `AGENT.md`.

## Requisitos

- Godot **4.7** (Forward+ / D3D12 no Windows)
- Placa de vídeo com suporte a Vulkan ou Direct3D 12

## Licença

Distribuído sob a licença MIT. Veja [LICENSE](LICENSE) para mais detalhes.


## Build de protótipo — mapa simples e menu mínimo

- `project.godot` abre `scenes/ui/main_menu.tscn` e registra `AudioManager` como autoload.
- `Board` instancia `assets/maps/arena_prototipo.glb` para a grade 9×9; se o GLB não estiver importado ou a escala for alterada, usa o fallback procedural com as mesmas cores chapadas.
- O GLB utiliza materiais PBR glTF explícitos (não depende de vertex colors). O `Board` também aplica uma paleta de `StandardMaterial3D` sem iluminação às malhas reconhecidas.
- A estrada é redesenhada em runtime pelo Godot com `BoxMesh` e materiais sem iluminação, acima do piso. Isso evita que a rota desapareça por incompatibilidade do importador GLB ou fique atrás dos tiles. Os inimigos recebem waypoints em Y=0.102, logo acima da estrada.
- A rota tem três faixas horizontais conectadas nas laterais. As 35 células do GLB correspondem a `Board._default_path()`.
- O menu contém somente HAND DEFENSE, JOGAR e SAIR. Sem subtítulo, controles, painel ou música.
- Permanecem somente efeitos de tiro comum, laser, morte de inimigo e conclusão da fase. As chaves de SFX são `shot_pew`, `laser`, `enemy_down` e `level_complete`.
- O Olho Laser continua sendo a quarta torre e reutiliza `assets/oleos.glb`.
- Antes de cada feixe, o Olho Laser faz uma antecipação de escala (squash e stretch) no modelo inteiro e só dispara depois dela. O recurso fica em `TowerData.anticipation_*` e está ativo no `eye_laser.tres`; o `frost.tres` também está habilitado para testes.
- Se `anticipation_duration` for maior que `fire_interval`, a animação limita a cadência (`max(fire_interval, anticipation_duration)`); o tiro não é cancelado pelo wind-up seguinte.
- `R` reinicia a fase em qualquer momento (BUILD, WAVE ou fim de jogo).
- Se o mapa aparecer cinza após uma mudança, apague somente `.godot/imported` e reabra o projeto para forçar a reimportação. Não apague `assets/`.

## Testes necessários no Godot 4.7

1. Abra `project.godot` e aguarde a importação do GLB e dos WAVs.
2. Execute F5 e confirme que o menu apresenta apenas título, Jogar e Sair.
3. Clique em Jogar e verifique se a estrada está acima dos tiles e se acompanha a rota dos inimigos.
4. Coloque cada torre, incluindo o Olho Laser, e confirme o encaixe na grade.
5. Confirme que o Olho Laser faz squash/stretch antes do feixe e que as demais torres não deformam.
6. Inicie as ondas, confira os disparos e os sons de tiro/morte/vitória.
7. Pressione `R` em BUILD, durante uma onda e no fim de jogo para confirmar o restart.

**Limitação:** o projeto foi carregado no Godot 4.7 headless (scripts e cenas sem erros de parse/importação), mas o gameplay visual e a reprodução dos WAVs precisam ser confirmados no editor.
