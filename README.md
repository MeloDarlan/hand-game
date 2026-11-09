# hand game

Jogo 3D em **Godot 4.7** onde você controla uma **mão gigante** com o mouse.
A mão fecha, agarra, arrasta e arremessa objetos físicos pela cena.

![Godot](https://img.shields.io/badge/Godot-4.7-478CBF?logo=godotengine&logoColor=white)
![Renderer](https://img.shields.io/badge/Renderer-Forward%2B-478CBF)
![Physics](https://img.shields.io/badge/Physics-Jolt%20Physics-478CBF)
![License](https://img.shields.io/badge/License-MIT-green)

## Controles

| Ação | Comando |
| --- | --- |
| Mover a mão | Mouse |
| Fechar a mão (CATCH) e tentar pegar | Clique esquerdo |
| Arrastar o objeto pego | Manter o botão pressionado e mover |
| Soltar / arremessar | Soltar o botão |
| Devolver as esferas de teste ao spawn | `R` |
| Alternar modo de movimento | `M` |

## Modos de movimento

- **FOLLOW_MOUSE** (padrão): a palma segue o cursor num plano paralelo à câmera,
  com alcance limitado a partir da base.
- **FIXED_ARM**: a base do antebraço fica fixa e o braço inteiro pivota para
  apontar ao mouse.

## Como rodar

1. Instale o [Godot 4.7](https://godotengine.org/download) (versão standard, não precisa do .NET).
2. Clone o repositório:
   ```bash
   git clone https://github.com/MeloDarlan/hand-game.git
   ```
3. Abra o Godot, clique em **Import**, selecione o arquivo `project.godot` desta pasta.
4. Pressione **F5** para jogar.

Pela linha de comando (Windows):

```powershell
& 'C:\caminho\para\Godot_v4.7-stable_win64.exe' --path 'D:\hand-game'
```

## Estrutura do projeto

```text
scenes/main.tscn                cena principal (câmera, luzes, mão, esferas)
scenes/hand_player.tscn         wrapper da mão: PalmPivot, HoldPoint, GrabArea, ArmEnd
scenes/grabbable.tscn           esfera pegável
scenes/cube.tscn                cubo pegável de teste
scripts/hand_controller.gd      mouse, modos de movimento, CATCH, grab, throw
scripts/grabbable.gd            física do objeto pego/solto
scripts/grabbables.gd           reset com R
scripts/arm_jelly.gd            simulação de molas do braço (efeito jelly)
assets/hand-game.glb            modelo da mão + animações CATCH/IDLE
assets/oleos.glb                modelo auxiliar
resources/jelly_arm.gdshader    deformação do antebraço
```

## Requisitos

- Godot **4.7** (Forward+ / D3D12 no Windows)
- Placa de vídeo com suporte a Vulkan ou Direct3D 12

## Licença

Distribuído sob a licença MIT. Veja [LICENSE](LICENSE) para mais detalhes.
