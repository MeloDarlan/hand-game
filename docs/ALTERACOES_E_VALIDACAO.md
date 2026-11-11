# Alterações desta build de protótipo

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

## Áudio

- Sem música de fundo.
- Efeitos pontuais: tiro comum, laser, morte de inimigo e conclusão da fase.
- Os WAVs são sintetizados para este projeto, não são samples extraídos de jogos comerciais.

## Validação

- Verificações estáticas: integridade do GLB, 35 waypoints, caminhos de recursos e integridade do ZIP.
- Não houve execução do Godot neste ambiente. Importação, compilação e gameplay devem ser testados no Godot 4.7.
