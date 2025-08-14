# 🥊 Rinha de Backend - 2025

Projeto desenvolvido para participar da [Rinha de Backend 2025](https://github.com/zanfranceschi/rinha-de-backend-2025), utilizando Free Pascal.

## 🚀 Tecnologias Utilizadas

- **Linguagem:** Free Pascal  
- **Framework:** mORMot2  
- **Persistencia:** Própria com controle em memória

## 📄 Como Rodar

1. Clone o repositório:
   ```bash
   git clone https://github.com/diogoloff/api-fpc-rinha2025

2. Clone o repositório da imagem e fontes da persistencia:
   ```bash
   git clone https://github.com/diogoloff/persistencia-fpc-rinha2025

## Dificuldades enfrentadas

Durante a Rinha, minha ideia inicial era utilizar Delphi com DataSnap e persistência em Firebird, mas acabei enfrentando limitações de processamento, especialmente relacionadas ao DataSnap. A tecnologia possui um sistema automático de escalonamento de workers conforme a carga aumenta, o que, a partir dos 40 segundos de teste elevava drasticamente o número de threads e consequentemente o consumo de CPU. Embora seja uma solução robusta, o perfil altamente limitado do desafio da Rinha tornou inviável seu uso nesse contexto. As mesmas colocações valem para o Horse, apesar de um pouco mais leve que o DataSnap

Quanto à persistência, criei um sistema em memória com inclusão e leitura de dados próprio. Avaliei o uso do Redis, mas tanto em Delphi como em FPC não existe nativo. Encontrei apenas uma biblioteca antiga no GitHub, compatível com uma versão desatualizada do Redis. Apesar de ter tentado integrá-la, enfrentei sérios problemas de concorrência e inconsistência nos dados. Diante disso, desenvolvi uma solução própria que se mostrou mais estável e eficiente para o desafio.

Além disto tive e ainda tenho dificuldades com NGINX, a aplicação rodando diretamente sem o load balancer apresenta desempenho superior mesmo com as 500vu do teste em uma unica instância, já com o NGINX o tempo de resposta cai de forma consideravel, infelizmente, é uma tecnologia que nunca utilizei e tive que aprender alguma coisa para este desafio, esta será uma tecnologia que irei começar estudar.
