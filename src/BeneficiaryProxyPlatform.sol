// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {MinerAPI} from "@zondax/filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {SendAPI} from"@zondax/filecoin-solidity/contracts/v0.8/SendAPI.sol";
import {CommonTypes} from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import {MinerTypes} from "@zondax/filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import {FilAddresses} from "@zondax/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {BigInts} from "@zondax/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {PrecompilesAPI} from"@zondax/filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";


library FilAddressUtil {
    function bytesToAddress(bytes memory bys) internal pure returns (address addr) {
        require(bys.length == 20);
        assembly {
            addr := mload(add(bys, 20))
        }
    }

    function ethAddress(CommonTypes.FilActorId actor) internal pure returns (address){
        return bytesToAddress(abi.encodePacked(hex"ff0000000000000000000000", CommonTypes.FilActorId.unwrap(actor)));
    }

    function isFilF0Address(address addr) internal pure returns (bool){
        if ((uint160(addr) >> 64) == 0xff0000000000000000000000) {
            return true;
        }

        return false;
    }

    function fromEthAddress(address addr) internal pure returns (CommonTypes.FilAddress memory){
        if (isFilF0Address(addr)) {
            return FilAddresses.fromActorID(uint64(uint160(addr)));
        }

        return FilAddresses.fromEthAddress(addr);
    }

    function resolveEthAddress(address addr) internal view returns (uint64) {
        if (isFilF0Address(addr)) {
            return uint64(uint160(addr));
        }

        return PrecompilesAPI.resolveEthAddress(addr);
    }
}

    struct BeneficiaryInfo {
        uint128 beneficiaryReleaseHeight;
        uint128 investedReleaseHeight;
        uint128 investedFunds;
        uint128 withdrawnFunds;
        address[] beneficiarys; //收益人
        address[] investors; //质押人
        //address[] voters; //投票人
        uint32[] beneficiarysAllotRatio; //收益人分配比例
        uint32[] investorsAllotRatio; //质押人分配比例
    }

    enum ProposalType{
        None,
        UpdateBeneficiary,
        ResetBeneficiaryReleaseHeight,
        ResetInvestedReleaseHeight,
        EarlyWithdrawalOfInvestor,
        UpdateBeneficiarysAllotRatio,
        ResetInvestedFunds,
        //ResetVoters,
        End
    }

    struct VoteInfo {
        address addr;
        bool isApproved;
    }

    struct ProposalInfo {
        uint8 proposalType;
        int8 stat;  //-1:投票反对 0:未有结果 1:执行成功 2:执行失败
        bytes params;
        VoteInfo[] voteInfos;
    }

    struct RegisterBeneficiaryInfo {
        uint128 beneficiaryReleaseHeight;
        uint128 investedReleaseHeight;
        uint128 investedFunds;
        address[] beneficiarys;
        uint32[] beneficiarysAllotRatio;
        address[] investors;
        uint32[] investorsAllotRatio;
    }

uint128  constant ensemble = 10000;


library BeneficiaryProxyPlatformLib {
    function sendByAllotRatio(address[] storage receiver, uint32[] storage allotRatio, uint128 amount) internal {
        uint length = receiver.length;
        for (uint i = 0; i < length; i++) {
            SendAPI.send(FilAddressUtil.fromEthAddress(receiver[i]), uint256(amount * allotRatio[i] / ensemble));
        }
    }


    function checkDupAddrs(address[] memory addrs) internal pure returns (bool){
        uint256 length = addrs.length;
        if (length < 2) {
            return false;
        }

        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (addrs[i] == addrs[j]) {
                    return true;
                }
            }
        }

        return false;
    }
}

contract Factory {
    BeneficiaryProxyPlatform public BPP;
    constructor (address renter){
        Proposal proposal = new Proposal();
        BeneficiaryProxy beneficiaryProxy = new BeneficiaryProxy();
        BPP = new BeneficiaryProxyPlatform(address(beneficiaryProxy), address(proposal), renter);
    }
}

contract BeneficiaryProxyPlatform {
    using BigInts for *;

    mapping(uint64 => BeneficiaryInfo) private rosters;
    mapping(uint64 => ProposalInfo[]) private proposalsRepo;

    address public Renter;
    address public immutable ProposalCont;
    address public immutable BeneficiaryProxyCont;


    modifier onlyRenter(){
        require(msg.sender == Renter);
        _;
    }

    receive() external payable {}

    constructor(address beneficiaryProxyCont, address proposalCont, address renter){
        BeneficiaryProxyCont = beneficiaryProxyCont;
        ProposalCont = proposalCont;
        Renter = renter;
    }

    function getRoster(uint64 actor) public view returns (BeneficiaryInfo memory){
        return rosters[actor];
    }

    function getProposals(uint64 actor) public view returns (ProposalInfo[]memory){
        return proposalsRepo[actor];
    }

    function changeRent(address newRenter) external payable onlyRenter {
        Renter = newRenter;
    }

    function rent(address addr, uint256 balance) external payable onlyRenter {
        SendAPI.send(FilAddressUtil.fromEthAddress(addr), balance);
    }

    function registerBeneficiary(uint64 actor, RegisterBeneficiaryInfo memory info) public payable {
        (bool success,) = BeneficiaryProxyCont.delegatecall(abi.encodeWithSignature("registerBeneficiary(uint64,(uint128,uint128,uint128,address[],uint32[],address[],uint32[]))", actor, info));
        require(success);
    }

    function withdraw(uint64 actor, int256 amount) public payable {
        (bool success,) = BeneficiaryProxyCont.delegatecall(abi.encodeWithSignature("withdraw(uint64,int256)", actor, amount));
        require(success);
    }

    function changeBeneficiary(uint64 actor, address newAddr) public payable {
        (bool success,) = BeneficiaryProxyCont.delegatecall(abi.encodeWithSignature("changeBeneficiary(uint64,address)", actor, newAddr));
        require(success);
    }

    function changeInvestor(uint64 actor, address newAddr) public payable {
        (bool success,) = BeneficiaryProxyCont.delegatecall(abi.encodeWithSignature("changeInvestor(uint64,address)", actor, newAddr));
        require(success);
    }

    //提案
    function propose(uint64 actor, uint8 proposalType, bytes calldata params) public payable returns (uint256){
        (bool success, bytes memory raw_response) = ProposalCont.delegatecall(abi.encodeWithSignature("propose(uint64,uint8,bytes)", actor, proposalType, params));
        require(success);

        return abi.decode(raw_response, (uint256));
    }

    function vote(uint64 actor, uint64 proposalID, bool isApproved) public payable {
        (bool success,) = ProposalCont.delegatecall(abi.encodeWithSignature("vote(uint64,uint64,bool)", actor, proposalID, isApproved));
        require(success);
    }
}


contract BeneficiaryProxy {
    using BigInts for *;

    mapping(uint64 => BeneficiaryInfo) private rosters;
    mapping(uint64 => ProposalInfo[]) private proposalsRepo;

    constructor(){}

    function registerBeneficiary(uint64 actor, RegisterBeneficiaryInfo memory info) public payable {
        require(info.beneficiarys.length == info.beneficiarysAllotRatio.length);
        require(info.investors.length == info.investorsAllotRatio.length);
        require(info.beneficiarys.length > 0);
        require(info.beneficiaryReleaseHeight <= info.investedReleaseHeight);

        require(!BeneficiaryProxyPlatformLib.checkDupAddrs(info.beneficiarys));

        uint256 ratio = 0;
        for (uint i = 0; i < info.beneficiarysAllotRatio.length; i++) {
            ratio += info.beneficiarysAllotRatio[i];
        }
        require(ratio == ensemble);

        if (info.investors.length != 0) {
            require(!BeneficiaryProxyPlatformLib.checkDupAddrs(info.investors));

            ratio = 0;
            for (uint i = 0; i < info.investorsAllotRatio.length; i++) {
                ratio += info.investorsAllotRatio[i];
            }
            require(ratio == ensemble);
        }

        MinerTypes.GetOwnerReturn memory ownerReturn = MinerAPI.getOwner(CommonTypes.FilActorId.wrap(actor));
        uint64 ownerID = PrecompilesAPI.resolveAddress(ownerReturn.owner);
        uint64 sendID = FilAddressUtil.resolveEthAddress(msg.sender);
        require(ownerID == sendID, "only the owner can register");

        MinerTypes.GetBeneficiaryReturn memory beneficiaryReturn = MinerAPI.getBeneficiary(CommonTypes.FilActorId.wrap(actor));

        uint64 thisID = FilAddressUtil.resolveEthAddress(address(this));
        uint64 minerBeneficiaryID = PrecompilesAPI.resolveAddress(beneficiaryReturn.active.beneficiary);
        if (thisID == minerBeneficiaryID) {
            (uint256 _quota, bool failure0) = beneficiaryReturn.active.term.quota.toUint256();
            require(!failure0, "legal return parameter");

            (uint256 used_quota, bool failure1) = beneficiaryReturn.active.term.used_quota.toUint256();
            require(!failure1, "legal return parameter");

            if ((used_quota < _quota) && (uint256(int256(CommonTypes.ChainEpoch.unwrap(beneficiaryReturn.active.term.expiration))) > block.number)) {
                revert("the owner is already registered");
            }
        }

        uint64 newBeneficiaryID = PrecompilesAPI.resolveAddress(beneficiaryReturn.proposed.new_beneficiary);
        require(thisID == newBeneficiaryID);

        MinerAPI.changeBeneficiary(CommonTypes.FilActorId.wrap(actor), MinerTypes.ChangeBeneficiaryParams(FilAddressUtil.fromEthAddress(address(this)), beneficiaryReturn.proposed.new_quota, beneficiaryReturn.proposed.new_expiration));

        delete proposalsRepo[actor];
        rosters[actor] = BeneficiaryInfo(
            info.beneficiaryReleaseHeight,
            info.investedReleaseHeight,
            info.investedFunds,
            0,
            info.beneficiarys,
            info.investors,
            //info.voters,
            info.beneficiarysAllotRatio,
            info.investorsAllotRatio
        );
    }

    function withdraw(uint64 actor, int256 amount) public payable {
        BeneficiaryInfo storage roster = rosters[actor];
        require(block.number >= roster.beneficiaryReleaseHeight);

        CommonTypes.BigInt memory amount_withdrawn = MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(actor), BigInts.fromInt256(amount));
        (uint256 balance, bool failure) = amount_withdrawn.toUint256();
        require(!failure, "legal return parameter");

        if (block.number >= roster.investedReleaseHeight && roster.withdrawnFunds < roster.investedFunds) {
            balance = balance - uint256(withdrawForInvestor(roster, uint128(balance)));
            if (balance == 0) {
                return;
            }
        }

        BeneficiaryProxyPlatformLib.sendByAllotRatio(roster.beneficiarys, roster.beneficiarysAllotRatio, uint128(balance));
    }

    function changeBeneficiary(uint64 actor, address newAddr) public payable {
        address[] storage beneficiarys = rosters[actor].beneficiarys;
        uint length = beneficiarys.length;
        for (uint i = 0; i < length; i++) {
            if (beneficiarys[i] == msg.sender) {
                beneficiarys[i] = newAddr;

                require(!BeneficiaryProxyPlatformLib.checkDupAddrs(beneficiarys));
                return;
            }
        }
    }

    function changeInvestor(uint64 actor, address newAddr) public payable {
        address [] storage investors = rosters[actor].investors;
        uint length = investors.length;
        for (uint i = 0; i < length; i++) {
            if (investors[i] == msg.sender) {
                investors[i] = newAddr;

                require(!BeneficiaryProxyPlatformLib.checkDupAddrs(investors));
                return;
            }
        }
    }

    function withdrawForInvestor(BeneficiaryInfo storage roster, uint128 balance) private returns (uint128){
        uint128 amount_withdrawn = roster.investedFunds - roster.withdrawnFunds;
        if (amount_withdrawn > balance) {
            amount_withdrawn = balance;
        }

        roster.withdrawnFunds += amount_withdrawn;
        BeneficiaryProxyPlatformLib.sendByAllotRatio(roster.investors, roster.investorsAllotRatio, amount_withdrawn);
        return amount_withdrawn;
    }
}

contract Proposal {
    using BigInts for *;

    mapping(uint64 => BeneficiaryInfo) private rosters;
    mapping(uint64 => ProposalInfo[]) private proposalsRepo;

    constructor(){}

    function propose(uint64 actor, uint8 proposalType, bytes calldata params) public payable returns (uint256){
        require(proposalType > 0);
        require(proposalType < uint8(ProposalType.End));

        BeneficiaryInfo storage roster = rosters[actor];

        if (proposalType == uint8(ProposalType.UpdateBeneficiary)) {
            abi.decode(params, (address, int256, int64));
        } else if (proposalType == uint8(ProposalType.UpdateBeneficiarysAllotRatio)) {
            (address[]memory _beneficiarys, uint32[]memory beneficiarysAllotRatio) = abi.decode(params, (address[], uint32[]));
            require(_beneficiarys.length == beneficiarysAllotRatio.length);
            require(_beneficiarys.length > 0);
            require(!BeneficiaryProxyPlatformLib.checkDupAddrs(_beneficiarys));

            uint256 ratio = 0;
            for (uint i = 0; i < beneficiarysAllotRatio.length; i++) {
                ratio += beneficiarysAllotRatio[i];
            }

            require(ratio == ensemble);
            //当执行时需要检查所有voters是否还在beneficiarys和investors
        } else if (proposalType == uint8(ProposalType.EarlyWithdrawalOfInvestor)) {
            uint128 _earlyWithdrawalOfInvestorFunds = abi.decode(params, (uint128));

            require(_earlyWithdrawalOfInvestorFunds <= (roster.investedFunds - roster.withdrawnFunds), "amount of withdrawal is exceeded the limit");
        } else {
            abi.decode(params, (uint128));
        }

        ProposalInfo[] storage proposals = proposalsRepo[actor];
        proposals.push();
        uint256 proposalID = proposals.length - 1;
        ProposalInfo storage proposal = proposals[proposalID];

        proposal.proposalType = proposalType;
        proposal.params = params;

        address[] memory beneficiarys = roster.beneficiarys;
        address[]  memory investors = roster.investors;
        (address[]memory voters,uint256 votersLen) = getVoters(beneficiarys, investors);

        for (uint i = 0; i < votersLen; i++) {
            if (msg.sender == voters[i]) {
                proposal.voteInfos.push(VoteInfo(msg.sender, true));

                uint8 votestat = calVoteStat(proposal.voteInfos, voters, votersLen);

                if (votestat == 2) {
                    proposal.stat = - 1;
                } else if (votestat == 1) {
                    implementProposal(actor, roster, proposal);
                }

                break;
            }
        }

        return proposalID;
    }

    function vote(uint64 actor, uint64 proposalID, bool isApproved) public payable {
        ProposalInfo storage proposalInfo = proposalsRepo[actor][proposalID];
        if (proposalInfo.stat != 0) {
            revert();
        }

        BeneficiaryInfo storage roster = rosters[actor];

        address[]memory beneficiarys = roster.beneficiarys;
        address[]memory investors = roster.investors;
        (address[]memory voters,uint256 votersLen) = getVoters(beneficiarys, investors);

        uint256 voteInfosLen = proposalInfo.voteInfos.length;

        bool voted = false;
        bool isVoter = false;

        for (uint i = 0; i < votersLen; i++) {
            if (voters[i] == msg.sender) {
                for (uint j = 0; j < voteInfosLen; j++) {
                    if (proposalInfo.voteInfos[j].addr == msg.sender) {
                        proposalInfo.voteInfos[j].isApproved = isApproved;
                        voted = true;
                        break;
                    }
                }

                if (voted == false) {
                    proposalInfo.voteInfos.push(VoteInfo(msg.sender, isApproved));
                }

                isVoter = true;
                break;
            }
        }

        require(isVoter, "the caller must be a beneficiary or a investor");

        uint8 votestat = calVoteStat(proposalInfo.voteInfos, voters, votersLen);

        if (votestat == 2) {
            proposalInfo.stat = - 1;
        } else if (votestat == 1) {
            implementProposal(actor, roster, proposalInfo);
        }
    }

    function implementProposal(uint64 actor, BeneficiaryInfo storage roster, ProposalInfo storage proposalInfo) private {
        uint8 proposalType = proposalInfo.proposalType;

        bool isOk;
        if (proposalType == uint8(ProposalType.UpdateBeneficiary)) {
            bool isDeleted;
            (isDeleted, isOk) = implementUpdateBeneficiary(actor, proposalInfo.params);
            if (isDeleted) {
                return;
            }
        } else if (proposalType == uint8(ProposalType.ResetBeneficiaryReleaseHeight)) {
            isOk = implementResetBeneficiaryReleaseHeight(roster, proposalInfo.params);
        } else if (proposalType == uint8(ProposalType.ResetInvestedReleaseHeight)) {
            isOk = implementResetInvestedReleaseHeight(roster, proposalInfo.params);
        } else if (proposalType == uint8(ProposalType.EarlyWithdrawalOfInvestor)) {
            isOk = implementEarlyWithdrawalOfInvestor(actor, roster, proposalInfo.params);
        } else if (proposalType == uint8(ProposalType.UpdateBeneficiarysAllotRatio)) {
            isOk = implementUpdateBeneficiarysAllotRatio(roster, proposalInfo.params);
        } else if (proposalType == uint8(ProposalType.ResetInvestedFunds)) {
            isOk = implementResetInvestedFunds(roster, proposalInfo.params);
        } else {
            revert("unkown proposalType");
        }

        if (isOk) {
            proposalInfo.stat = 1;
        } else {
            proposalInfo.stat = 2;
        }
    }

    function implementUpdateBeneficiary(uint64 actor, bytes memory params) private returns (bool, bool) {
        (address addr, int256 quota, int64 expiration) = abi.decode(params, (address, int256, int64));
        MinerAPI.changeBeneficiary(CommonTypes.FilActorId.wrap(actor), MinerTypes.ChangeBeneficiaryParams(FilAddressUtil.fromEthAddress(addr), BigInts.fromInt256(quota), CommonTypes.ChainEpoch.wrap(expiration)));


        if (addr != address(this)) {
            delete rosters[actor];
            delete proposalsRepo[actor];
            return (true, true);
        }

        return (false, true);
    }

    function implementResetBeneficiaryReleaseHeight(BeneficiaryInfo storage roster, bytes memory params) private returns (bool) {
        roster.beneficiaryReleaseHeight = abi.decode(params, (uint128));
        return true;
    }

    function implementResetInvestedReleaseHeight(BeneficiaryInfo storage roster, bytes memory params) private returns (bool) {
        roster.investedReleaseHeight = abi.decode(params, (uint128));
        return true;
    }

    function implementEarlyWithdrawalOfInvestor(uint64 actor, BeneficiaryInfo storage roster, bytes memory params) private returns (bool) {
        uint128 earlyWithdrawalOfInvestorFunds = abi.decode(params, (uint128));
        uint128 canWithdrawAmount = roster.investedFunds - roster.withdrawnFunds;
        if (earlyWithdrawalOfInvestorFunds > canWithdrawAmount) {
            earlyWithdrawalOfInvestorFunds = canWithdrawAmount;
        }

        CommonTypes.BigInt memory amount_withdrawn = MinerAPI.withdrawBalance(CommonTypes.FilActorId.wrap(actor), BigInts.fromInt256(int256(uint256(earlyWithdrawalOfInvestorFunds))));
        (uint256 balance, bool failure) = amount_withdrawn.toUint256();
        if (failure) {
            return false;
        }

        if (earlyWithdrawalOfInvestorFunds > uint128(balance)) {
            earlyWithdrawalOfInvestorFunds = uint128(balance);
        }

        roster.withdrawnFunds += earlyWithdrawalOfInvestorFunds;
        BeneficiaryProxyPlatformLib.sendByAllotRatio(roster.investors, roster.investorsAllotRatio, earlyWithdrawalOfInvestorFunds);

        return true;
    }

    function implementUpdateBeneficiarysAllotRatio(BeneficiaryInfo storage roster, bytes memory params) private returns (bool){
        (address[]memory beneficiarys, uint32[]memory beneficiarysAllotRatio) = abi.decode(params, (address[], uint32[]));

        roster.beneficiarys = beneficiarys;
        roster.beneficiarysAllotRatio = beneficiarysAllotRatio;

        return true;
    }

    function implementResetInvestedFunds(BeneficiaryInfo storage roster, bytes memory params) private returns (bool){
        roster.investedFunds = abi.decode(params, (uint128));

        return true;
    }

    function isBeneficiarysOrInvestors(address voter, address[]memory beneficiarys, address[]memory investors) internal pure returns (bool){
        for (uint256 i = 0; i < beneficiarys.length; i++) {
            if (voter == beneficiarys[i]) {
                return true;
            }
        }

        for (uint256 i = 0; i < investors.length; i++) {
            if (voter == investors[i]) {
                return true;
            }
        }

        return false;
    }

    function calVoteStat(VoteInfo[]memory voteInfos, address[]memory voters, uint256 votersLen) internal pure returns (uint8){
        if (voteInfos.length < votersLen) {
            return 0;
        }

        uint8 voteStat = 1; //1:投票通过, 2:投票没有通过 0:还有人没有投票

        for (uint256 i = 0; i < votersLen; i++) {
            uint8 current_votedstat;

            for (uint256 j = 0; j < voteInfos.length; j++) {
                if (voters[i] == voteInfos[j].addr) {
                    if (voteInfos[j].isApproved) {
                        current_votedstat = 1;
                    } else {
                        current_votedstat = 2;
                    }

                    break;
                }
            }

            if (current_votedstat == 0) {
                return 0;
            } else if (current_votedstat == 2) {
                voteStat = 2;
            }
        }

        return voteStat;
    }

    function getVoters(address[]memory beneficiarys, address[]memory investors) internal pure returns (address[]memory, uint256){
        address[]memory voters = new address[](beneficiarys.length + investors.length);
        for (uint256 i = 0; i < beneficiarys.length; i++) {
            voters[i] = beneficiarys[i];
        }

        uint256 next = beneficiarys.length;
        for (uint256 i = 0; i < investors.length; i++) {
            bool repeated;
            for (uint256 j = 0; j < beneficiarys.length; j++) {
                if (investors[i] == beneficiarys[j]) {
                    repeated = true;
                    break;
                }
            }

            if (!repeated) {
                voters[next] = investors[i];
                next++;
            }
        }

        return (voters, next);
    }
}