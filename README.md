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
| Ciclar torres | Scroll do mouse ou `1`/`2`/`3` |
| Alternar FOLLOW_MOUSE / FIXED_ARM | `M` |
| Cancelar / devolver torre | Clique direito, `Esc` ou clicar de novo no botão selecionado |
| Iniciar onda | `Espaço` ou botão "Iniciar onda" |
| Reiniciar após fim de jogo | `R` ou botão do overlay |
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
scenes/main.tscn                 cena principal
scenes/hand_player.tscn          mão: PalmPivot, HoldPoint, GrabArea, ArmJelly
scenes/ui/hud.tscn               top bar, toolbar e overlay de fim de jogo
scripts/camera_iso.gd            câmera isométrica ortográfica
scripts/board.gd                 grade, caminho, ocupação, highlight e range ring
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
assets/oleos.glb                 asset antigo (não usado no MVP)
```

As esferas/cubo/olho de teste do protótipo original continuam em `scenes/`, mas
não são mais instanciados na cena principal.

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

Os exports do `HandPlayer` e do `ArmJelly`/`OcclusionOutline` aplicam na hora
(setters + `apply_pose`); o `pinch_offset` sobrescreve o Transform do HoldPoint
na cena. O anel de validade acompanha o pé da peça.

## Pós-MVP

Tema e arte final, áudio/VFX, upgrades e venda de torres, mais torres/inimigos,
mapas com caminhos diferentes e ondas infinitas. O próximo passo de feel é
ajustar o swing da peça (`motion_*`) e, se quiser, adicionar reação no eixo de
profundidade. Se a escala da mão incomodar, ajustar `hand_scale` e o fade do
antebraço para reduzir a mão sem expor o corte. Detalhes em `AGENT.md`.

## Requisitos

- Godot **4.7** (Forward+ / D3D12 no Windows)
- Placa de vídeo com suporte a Vulkan ou Direct3D 12

## Licença

Distribuído sob a licença MIT. Veja [LICENSE](LICENSE) para mais detalhes.
