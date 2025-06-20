# Smartnodes

![Static Badge](https://img.shields.io/badge/v0.1.2-Smartnodes-pink?logo=) ![License](https://img.shields.io/badge/License-MIT-blue.svg) ![GitHub Repo stars](https://img.shields.io/github/stars/smartnodes-lab/smartnodes?style=social)

A framework for distributed resource sharing across peer-to-peer networks. Enables both local and global computational resource sharing, secured and incentivized by smart contracts.

## Introduction

Smartnodes is an ecosystem of peer-to-peer (P2P) networks designed to democratize access to computational resources and data-driven technologies. Our goal is to create an open and decentralized economy of distributed resources, empowering individuals and researchers with advanced tools while allowing people to monetize their hardware and time. Through smart contract-secured P2P networks, Smartnodes facilitates coordination of nodes and resources, driving advancements in artificial intelligence, data analysis, and other computational fields by providing secure, scalable, and flexible resource sharing.

For a deeper dive into Smartnodes' features, capabilities, and underlying principles, please refer to the
[lightpaper](docs/Lightpaper.md) and [documentation](https://smartnodes.ca/docs).

## Smart Contracts

At the core of the Smartnodes ecosystem lies a deployment of smart contracts that handle critical functions, ensuring seamless coordination, security, and transparency within the network.

## Smartnodes Core

Delegation of Roles and Permissions: role-specific permissions to methods ensure proper access control, validator-multisig control over job and state updates.
Storage of Worker and Validator History: keeps track of the history and reputation of users, along with storage of key user and node data.
Distribution of Rewards and Payments: native token SNO generated and distributed fairly among workers and validators. To be used for payment of services and securing validator nodes.

The main contract is managed by a multisignature wallet composed of active, collateralized validators. Contract updates operate on a rolling basis, where proposals are submitted every 10 minutes by a random selection of validators. The proposal receiving the most votes triggers a contract update with the provided information, such as user registration, worker information, and job-related events. Every state update is accompanied by a token generation event which is distributed fairly among participating validators and workers.

## Peer-to-Peer Networks

P2P networks built on Smartnodes enable efficient and secure interactions between workers and users to provide frictionless access to services. Individual networks are designed for a specific use case, and specialized to aggregate, distribute, and deliver a certain resource to users. Participants of the Smartnodes ecosystem possess a set of cryptographic keys that link their off-chain identity to the smart contract. This cryptographic layer ensures that only those with explicit authority to establish connections can do so, bolstering the security and authenticity of every interaction. Users can be classified into three categories.

Users interact with the Smartnodes network to submit job requests for access to the network’s pooled resources. They connect to validators to request jobs and initialize connections with workers for task execution.

Validators are responsible for the management of on and off-chain information. These validators operate on a specific P2P network, working to maintain a distributed hash table for node and job querying, while managing interactions between users and workers. They peer into worker-user processes, conduct proof-of-work requests to ensure proper actions, and update the job data structure with relevant information (e.g., worker reputations, job-specific data). Validators aggregate this off-chain data and vote on the integrity of these updates to the main contract, where information is finalized.

Workers are task-specific nodes that carry out jobs for users. They stand by and execute computational tasks assigned by validators, ensuring efficient completion of user requests.

Malicious workers are identified, and their reputations are updated or blacklisted based on their behavior.
By leveraging these mechanisms, Smartnodes creates a secure, efficient, and accessible platform for computational tasks, ensuring fair and transparent interactions among all participants.

## Donate

If you would like to support our work, consider buying us a coffee! Your contributions help us continue developing and improving Tensorlink.

<a href="https://www.buymeacoffee.com/smartnodes" target="_blank">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" style="width: 150px; height: auto;">
</a>
