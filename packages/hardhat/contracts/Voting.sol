// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import {SepoliaZamaFHEVMConfig} from "fhevm/config/ZamaFHEVMConfig.sol";
import {SepoliaZamaGatewayConfig} from "fhevm/config/ZamaGatewayConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";
import {LibString} from "solady/src/utils/LibString.sol";

import {console} from "hardhat/console.sol";

struct Proposal {
    address admin;
    string question;
    string[] metaOpts;
    uint256 startTime;
    uint256 endTime;
    uint64 thresholdToTally;
}

struct Predicate {
    uint64 opt;
    string op;
    einput handle;
}

struct Vote {
    euint64 rating;
    euint64[] metaVals;
}

contract Voting is SepoliaZamaFHEVMConfig, SepoliaZamaGatewayConfig, GatewayCaller {
    using LibString for string;
    // -- enum --


    // --- constant ---
    uint16 public constant MAX_QUESTION_LEN = 512;
    uint16 public constant MAX_OPTIONS = 32;

    // --- event ---
    event ProposalCreated(address indexed sender, uint64 indexed proposalId, uint256 startTime, uint256 endTime);
    event VoteCasted(address indexed sender, uint64 indexed proposalId);

    // --- storage ---
    address public admin;
    uint64 public nextProposalId = 0;
    mapping(uint64 => Proposal) public proposals;
    mapping(uint64 => Vote[]) public proposalVotes;
    mapping(uint64 => mapping(address => bool)) public hasVoted;
    mapping(address => euint64) public tallyResults;

    // --- viewer ---
    function getProposal(uint64 proposalId) public view returns (Proposal memory proposal) {
        require(proposalId < nextProposalId, "Invalid proposalId");
        proposal = proposals[proposalId];
    }

    function getVotesLen(uint64 proposalId) public view returns(uint256 voteLen) {
        require(proposalId < nextProposalId, "Invalid proposalId");
        Vote[] memory oneProposalVotes = proposalVotes[proposalId];
        voteLen = oneProposalVotes.length;
    }

    // --- write function ---

    function newProposal(
        string calldata _question,
        string[] calldata _metaOpts,
        uint64 _thresholdToTally,
        uint256 _startTime,
        uint256 _endTime
    ) public returns (Proposal memory proposal) {
        require (bytes(_question).length <= MAX_QUESTION_LEN, "Question exceed 512 bytes");
        require(_metaOpts.length <= MAX_OPTIONS, "Options exceed 32 options");
        require(_startTime < _endTime, "Start time is gte to end time");

        proposal = Proposal({
            admin: msg.sender,
            question: _question,
            metaOpts: _metaOpts,
            startTime: _startTime,
            endTime: _endTime,
            thresholdToTally: _thresholdToTally
        });

        uint64 proposalId = nextProposalId;
        proposals[proposalId] = proposal;
        nextProposalId += 1;

        emit ProposalCreated(msg.sender, proposalId, _startTime, _endTime);
    }

    function castVote(
        uint64 proposalId,
        einput rating,
        einput optVal1,
        einput optVal2,
        einput optVal3,
        bytes calldata inputProof
    ) public {
        require(proposalId < nextProposalId, "Invalid ProposalId.");
        require(!hasVoted[proposalId][msg.sender], "Sender has voted already.");

        Proposal storage proposal = proposals[proposalId];
        uint256 currentTS = block.timestamp;
        require(currentTS >= proposal.startTime, "The voting hasn't started yet.");
        require(currentTS <= proposal.endTime, "The voting has ended already.");

        euint64[] memory metaVals = new euint64[](3);
        metaVals[0] = TFHE.asEuint64(optVal1, inputProof);
        metaVals[1] = TFHE.asEuint64(optVal2, inputProof);
        metaVals[2] = TFHE.asEuint64(optVal3, inputProof);

        Vote memory vote = Vote({
            rating: TFHE.asEuint64(rating, inputProof),
            metaVals: metaVals
        });

        TFHE.allowThis(vote.rating);
        TFHE.allowThis(vote.metaVals[0]);
        TFHE.allowThis(vote.metaVals[1]);
        TFHE.allowThis(vote.metaVals[2]);

        proposalVotes[proposalId].push(vote);
        hasVoted[proposalId][msg.sender] = true;

        emit VoteCasted(msg.sender, proposalId);
    }

    function tallyUp(
        uint64 proposalId,
        string calldata op,
        Predicate calldata predicate,
        bytes calldata inputProof
    ) public {
        require(proposalId < nextProposalId, "Invalid ProposalId.");

        Proposal storage proposal = proposals[proposalId];
        Vote[] storage oneProposalVotes = proposalVotes[proposalId];
        require(oneProposalVotes.length >= proposal.thresholdToTally, "Vote threshold not reached yet");

        euint64 acc = TFHE.asEuint64(0);

        ebool eTrue = TFHE.asEbool(true);
        ebool eFalse = TFHE.asEbool(false);
        euint64 eZero = TFHE.asEuint64(0);

        euint64 predicateVal = TFHE.asEuint64(predicate.handle, inputProof);

        for (uint256 idx = 0; idx < oneProposalVotes.length; idx += 1) {
            euint64 checkVal = oneProposalVotes[idx].metaVals[predicate.opt];

            // console.log("predicateVal: %s", euint64.unwrap(predicateVal));
            // console.log("checkVal:     %s", euint64.unwrap(checkVal));

            ebool isEQ = TFHE.select(
                TFHE.asEbool(predicate.op.eq('EQ')),
                TFHE.eq(checkVal, predicateVal),
                eFalse
            );

            ebool isNE = TFHE.select(
                TFHE.asEbool(predicate.op.eq('NE')),
                TFHE.ne(checkVal, predicateVal),
                eFalse
            );

            ebool isGT = TFHE.select(
                TFHE.asEbool(op.eq('GT')),
                TFHE.gt(checkVal, predicateVal),
                eFalse
            );

            ebool isLT = TFHE.select(
                TFHE.asEbool(op.eq('LT')),
                TFHE.lt(checkVal, predicateVal),
                eFalse
            );

            ebool accepted = TFHE.select(
                isEQ,
                eTrue,
                TFHE.select(
                    isNE,
                    eTrue,
                    TFHE.select(
                        isGT,
                        eTrue,
                        TFHE.select(isLT, eTrue, eFalse)
                    )
                )
            );

            euint64 val = TFHE.select(
                accepted,
                oneProposalVotes[idx].rating,
                eZero
            );

            acc = TFHE.add(acc, val);
        }

        tallyResults[msg.sender] = acc;

        TFHE.allowThis(acc);
        TFHE.allow(acc, msg.sender);
    }
}
