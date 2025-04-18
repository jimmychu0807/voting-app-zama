// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { einput, euint64 } from "fhevm/lib/TFHE.sol";

interface IVoting {
    enum AggregateOp {
        COUNT,
        SUM,
        MIN,
        MAX,
        AVG
    }

    enum PredicateOp {
        EQ,
        NE,
        GT,
        LT
    }

    enum RequestState {
        Initialized,
        Completed
    }

    struct Proposal {
        address admin;
        string question;
        string[] metaOpts;
        uint256 startTime;
        uint256 endTime;
        uint64 queryThreshold;
    }

    struct QueryRequest {
        uint64 proposalId;
        address owner;
        AggregateOp aggOp;
        Predicate[] predicates;
        bytes inputProof;
        euint64 acc;
        uint64 accSteps;
        RequestState state;
    }

    struct Predicate {
        uint64 metaOpt;
        PredicateOp op;
        einput handle;
    }

    struct Vote {
        euint64 rating;
        euint64[] metaVals;
    }

    // All the events
    event ProposalCreated(address indexed sender, uint64 indexed proposalId, uint256 startTime, uint256 endTime);
    event VoteCasted(address indexed sender, uint64 indexed proposalId);
    event QueryRequestCreated(uint64 reqId, address owner);
    event QueryRequestDeleted(uint64 reqId);
    event QueryExecutionCompleted(uint64 reqId);
    event QueryExecutionRunning(uint64 reqId, uint64 accSteps, uint64 ttl);
}
