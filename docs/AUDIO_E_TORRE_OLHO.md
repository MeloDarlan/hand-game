# Torre Olho Laser e áudio simplificado

## Olho Laser
- O visual reutiliza `assets/oleos.glb`, o mesmo modelo verde já presente em `scenes/eye.tscn`.
- O recurso `resources/towers/eye_laser.tres` define custo, alcance, dano, intervalo e modo Laser.
- `TowerPiece` continua sendo um `Grabbable` único. O olho é apenas o visual filho da cabeça articulada; o feixe é um efeito temporário e o dano é aplicado diretamente ao inimigo.
- A orientação do modelo usa `aim_yaw_offset_degrees = 180` porque a pupila do GLB está voltada para o eixo local -Z.

## Áudio
- Não há trilha musical nem música de menu.
- Só são reproduzidos: disparo normal, disparo laser, morte de inimigo e conclusão da última onda.
- Os quatro WAVs foram sintetizados para este projeto em estilo de efeitos curtos de console portátil; não são cópias de sons de jogos existentes.
- O catálogo do [効果音ラボ / Sound Effect Lab — Botões e sons de sistema](https://soundeffect-lab.info/sound/button/) inspirou o caráter curto e eletrônico; a categoria [Combate](https://soundeffect-lab.info/sound/battle/) inspirou os rótulos de efeitos de magia e impacto. Os arquivos originais do site não foram embutidos nesta build, porque o ambiente não conseguiu obter os arquivos de áudio diretamente.
- Segundo os [termos do Sound Effect Lab](https://soundeffect-lab.info/agreement/), os sons do site podem ser usados gratuitamente inclusive comercialmente, sem obrigação de crédito, mas a redistribuição isolada é restrita. Esta build evita redistribuir amostras do site.

## Menu
- Menu mínimo: título, Jogar e Sair. Não exibe controles, subtítulo ou painel.
- Sem efeitos sonoros de navegação e sem música.

## Validação pendente
Executar no Godot 4.7 e verificar: importação do GLB do olho, orientação da pupila, alinhamento do ponto inicial do laser, alcance, dano, sinais de vitória e reprodução dos quatro WAVs.
