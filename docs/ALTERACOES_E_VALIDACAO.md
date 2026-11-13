# Alterações desta build de protótipo

Esta build acumula as mudanças desde o giro do tabuleiro com `Q`/`E`: o
desfoque de distância (implementado e **desativado**), a mão livre pela tela, a
margem de queda na borda e a animação de queda com estorno parcial.

## Mapa simples

- Arquivo visual: `assets/maps/arena_prototipo.glb`.
- Prévia superior: `assets/maps/preview_arena_prototipo.png`.
- Mapa 9×9 com cores chapadas, sem imagens de textura.
- Piso verde em blocos, estrada bege contínua e elevada, moldura escura, entrada e núcleo azul.
- A estrada é visual; `scripts/board.gd` continua sendo a fonte da verdade para células, rota, ocupação e posições dos inimigos.
- O GLB e `Board._default_path()` usam os mesmos 35 waypoints. A superfície da estrada e os waypoints estão em Y=0.084.
- Se o GLB ainda não tiver sido importado, o `Board` cria um fallback procedural com a mesma paleta básica.

## Menu inicial

- Título `HAND DEFENSE`.
- Botões `JOGAR` e `SAIR`.
- Sem painel informativo, instruções, subtítulo, animações ou música.

## Gameplay preservado

- O modelo `assets/oleos.glb` continua sendo usado pela torre Olho Laser.
- O olho continua sendo a quarta torre e dispara um feixe verde com dano direto.
- As mecânicas de captura, posicionamento, ondas e inimigos permanecem na arquitetura original.

## Giro do tabuleiro (Q/E)

- `Q` gira 90° para a esquerda e `E` para a direita, **somente em BUILD**. Cada toque soma um passo ao alvo acumulado; o input com `event.echo` é ignorado, então segurar a tecla não repete.
- A animação usa `TRANS_BACK`/`EASE_OUT` (`rotation_duration = 0.34`) para passar um pouco do ponto e voltar (bounce). Toques encadeados matam o tween e redirecionam a partir do ângulo atual.
- As torres são `RigidBody3D` filhas do `Board`, mas o physics server não acompanha a rotação do pai. O giro usa `tween_method` (`_apply_board_angle`), que chama `TowerPiece.sync_visual_to()` no mesmo passo do Tween (sem atraso de 1 frame). No fim, `_finalize_placed_towers()` teleporta o corpo com `place()`/`body_set_state`.
- Fora de BUILD o `GameManager` desliga `rotation_enabled`; o setter finaliza o giro imediatamente, encaixa o ângulo e reposiciona as torres. `world_to_cell`, `cell_to_world`, highlights e waypoints usam o transform local e continuam corretos com o tabuleiro girado.

## Queda de peça fora do tabuleiro

- A peça é paga no **CATCH** (ao aparecer na mão); encaixar em tile válido não cobra de novo.
- Cancelar/trocar a peça devolve 100% do valor pago.
- Soltar **fora dos limites do tabuleiro + `drop_edge_margin`** (1,0 por padrão) solta a peça: ela cai com giro, encolhe/apaga e é removida em ~0,7 s (`TowerPiece.play_drop_off_board`).
- Na faixa entre a borda do board e a margem de queda, a mão continua fechada (anel vermelho) para a peça não começar a cair visualmente sobre o tabuleiro.
- A queda desloca o visual para **trás do board** (`TowerPiece.drop_depth_offset`, 16 unidades no eixo da câmera). Como a câmera é ortográfica, a trajetória em tela não muda; a borda do board passa a cobrir a peça onde há sobreposição.
- A queda devolve apenas `BuildController.drop_refund_ratio` do valor (50% por padrão); a outra metade é o desconto.
- Derrubar fora uma torre que estava colocada também remove a torre e devolve o mesmo percentual do valor dela.
- Soltar em célula inválida **dentro** do board (caminho/ocupado) continua bloqueado: a mão permanece fechada.

## Mão livre pela tela

- `HandController.free_movement = true` remove o clamp ao redor do board: a mão segue o cursor por toda a tela.
- Com `false`, `board_margin` (0,8) volta a limitar o alvo ao redor da grade.
- Fora do board o alvo é inválido: o highlight some, o anel fica vermelho e soltar derruba a peça (regra acima). O encaixe continua só em célula válida.
- A pose do modelo da mão foi ajustada em `scenes/hand_player.tscn` (rotação em Y) e o `pinch_offset` da `main.tscn` passou para `(0, 0.6, -0.8)`. O plano da mão (`hand_plane_distance = 8.0`, default do script após remover o override 4.0 da cena) mantém braço e palma à frente de toda a borda do board.

## Áudio

- Sem música de fundo.
- Efeitos pontuais: tiro comum, laser, morte de inimigo e conclusão da fase.
- Os WAVs são sintetizados para este projeto, não são samples extraídos de jogos comerciais.

## Desfoque de distância (atualmente desabilitado)

- A `Camera3D` tem um `CameraAttributesPractical` com `dof_blur_far_distance = 31.0` e `dof_blur_near_distance = 0.09`, mas **o far blur está desligado**: `dof_blur_far_enabled` não está ativo na `scenes/main.tscn`. O tabuleiro, a mão e a peça renderizam nítidos do início ao fim.
- Quando o efeito foi testado, a profundidade do tabuleiro ia de ~24,3 (base) a ~34,7 (ponta superior) e o plano da mão ficava em ~21,6, fora do desfoque. A transição/amount ficavam no próprio `CameraAttributesPractical` para ajuste no Inspector.
- O **desfoque da peça segurada** (`held_piece_dof.gdshader`, criado pelo `OcclusionOutline`) também está inativo enquanto o far blur está desligado: o raio é derivado de `dof_blur_far_enabled`, `dof_blur_far_distance` e `dof_blur_far_transition` e retorna 0. O código permanece no projeto para religar.
- A **mão** usa `render_mode depth_draw_always` no shader do jelly porque o fade do antebraço escreve `ALPHA`; sem isso, um material transparente não grava profundidade e o DOF desfoca a mão junto com o fundo quando o efeito é religado.
- A mão fica no plano `hand_plane_distance = 8.0` (default do script; o override 4.0 foi removido da `main.tscn`), **à frente de toda a borda do board** (~24,3). Com 4.0 ela ficava em ~25,6 e o braço era cortado pela borda inferior, principalmente com a mão livre.
- Para religar: marcar `dof_blur_far_enabled`, ajustar `dof_blur_far_distance`/`dof_blur_far_transition`/`dof_blur_amount` no `CameraAttributesPractical` e manter `piece_blur_enabled` ligado no `OcclusionOutline`. Funciona só no Forward+/Mobile e não afeta a HUD nem as máscaras do outline.

## Validação

- Verificações estáticas: integridade do GLB, 35 waypoints, caminhos de recursos e integridade do ZIP.
- Giro `Q`/`E`: passos de 90° acumulados, bounce e sincronização visual das torres no mesmo passo do Tween; a conferência visual do bounce e do encaixe final ainda deve ser feita no editor.
- Desfoque de distância e desfoque da peça segurada: implementados, porém **desligados** nesta build (`dof_blur_far_enabled` inativo). Nada a validar visualmente enquanto estiverem desativados.
- Mão livre e plano da mão: teste headless temporário confirmou o alvo em ~10,5 unidades do centro (o clamp antigo parava em 5,3), o retorno ao limite com `free_movement = false`, e a mão em ~21,6 contra ~24,98 da célula mais próxima do board.
- Queda: cobrança no CATCH, estorno integral no cancelamento, encaixe sem cobrança extra, estorno de 50% na queda (peça nova e torre movida), bloqueio de tile inválido dentro do board, margem de 1,0 na borda (soltar a 4,6 mantém na mão; a 5,6 derruba) e profundidade da peça em queda atrás de toda a fundação do board (peça ~36,70 > board ~35,39) foram validados com teste headless temporário (removido depois).
- Parse/execução headless validados no Godot 4.7; gameplay visual (animação de queda, fade, giro, pose da mão e HUD) ainda deve ser confirmado no editor.
