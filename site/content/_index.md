---
title: pdmos.pt
---

## O projecto

O pdmos é um servidor partilhado por um grupo de amigos de Porto de Mós. Corre numa única
máquina, a **lena**, alojada na Hetzner, e toda a sua configuração é pública em
[github.com/pdmos/infra](https://github.com/pdmos/infra). Os serviços são para uso do grupo;
não há registo aberto.

## Conta

Todos os serviços usam a mesma conta, a **Fuas ID**, gerida em
[id.pdmos.pt](https://id.pdmos.pt). Não há palavra-passe: a entrada faz-se com uma *passkey*,
guardada no telemóvel ou no computador (Face ID, impressão digital, PIN do sistema ou chave física).

Para ter conta, fala com o Afonso ou com o Diogo. Recebes um link de acesso único; ao abri-lo,
registas a tua primeira passkey. Podes depois acrescentar outras em
[id.pdmos.pt](https://id.pdmos.pt), uma por dispositivo.

## Chat

O chat é um servidor [Matrix](https://matrix.org) em `pdmos.pt`, com salas de grupo, mensagens
directas e chamadas de voz e vídeo. Só comunica com contas do próprio servidor.

1. Instala um cliente: **Element X** (iPhone e Android), **Element** (web ou computador) ou
   **FluffyChat**.
2. Ao entrar, indica `pdmos.pt` como servidor.
3. Escolhe entrar com a Fuas ID e confirma com a passkey.

As chamadas de voz e vídeo funcionam no Element X e no Element. Na sala **Gabinete do
Presidente** vive o Jay Vala, um bot que anuncia os eventos do município todas as manhãs e
responde quando lhe falam.

## Correio

Há endereços `@pdmos.pt`, criados à mão pelo Afonso ou pelo Diogo. O correio não usa a Fuas ID:
cada endereço tem a sua palavra-passe. Configuração para qualquer cliente de correio:

| | Servidor | Porta | Segurança |
|---|---|---|---|
| Receber (IMAP) | `mail.pdmos.pt` | 993 | TLS |
| Enviar (SMTP) | `mail.pdmos.pt` | 587 | STARTTLS |

O nome de utilizador é o endereço completo.

## Manga

[manga.pdmos.pt](https://manga.pdmos.pt) é uma biblioteca de manga servida pelo
[Komga](https://komga.org). Entra com a Fuas ID; a conta é criada na primeira entrada. O Komga
lê-se no browser ou em apps compatíveis, como o Mihon.

## Ajuda

Para contas, acessos ou problemas, fala com o Afonso ou com o Diogo. Para questões sobre o
servidor em si, o sítio certo é o repositório [github.com/pdmos/infra](https://github.com/pdmos/infra).
