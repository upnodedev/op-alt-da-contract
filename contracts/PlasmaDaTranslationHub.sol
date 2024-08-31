// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract PlasmaDaTranslationHub is EIP712 {
    error InvalidSignature();
    error DuplicatedSubmission();

    mapping(address => mapping(bytes32 => mapping(bytes32 => bytes)))
        public translation;
    mapping(address => mapping(bytes32 => bytes32[])) dataProviders;
    mapping(address => address[]) extendedAddresses;

    event TranslationSubmitted(
        address indexed submitter,
        bytes32 indexed dataHash,
        bytes32 indexed da,
        bytes cid
    );

    event Extend(address indexed newSubmitter, address indexed oldSubmitter);

    struct DaCid {
        bytes32 da;
        bytes cid;
    }

    struct BatchSubmitInput {
        bytes32 dataHash;
        bytes32 da;
        bytes cid;
    }

    struct DelegatedSubmitInput {
        bytes32 dataHash;
        bytes32 da;
        bytes cid;
        bytes signature;
    }

    // Define the type hash for the struct
    bytes32 private constant SUBMIT_TYPEHASH =
        keccak256("PlasmaDaSubmit(bytes32 dataHash,bytes32 da,bytes cid)");

    constructor() EIP712("PlasmaDaTranslationHub", "1") {}

    function _submit(
        address submitter,
        bytes32 dataHash,
        bytes32 da,
        bytes calldata cid
    ) internal {
        // This prevent hacked batcher private key from destroying the data availability
        // If override is required, use a new batcher key and extend it to the old key
        if (translation[submitter][dataHash][da].length != 0) {
            revert DuplicatedSubmission();
        }

        translation[submitter][dataHash][da] = cid;
        dataProviders[submitter][dataHash].push(da);

        emit TranslationSubmitted(submitter, dataHash, da, cid);
    }

    function submit(bytes32 dataHash, bytes32 da, bytes calldata cid) external {
        _submit(msg.sender, dataHash, da, cid);
    }

    function batchSubmit(
        BatchSubmitInput[] calldata submissions
    ) external {
        unchecked {
            uint256 len = submissions.length;
            for (uint256 i; i < len; ++i) {
                _submit(
                    msg.sender,
                    submissions[i].dataHash,
                    submissions[i].da,
                    submissions[i].cid
                );
            }
        }
    }

    function verifySignature(
        address submitter,
        DelegatedSubmitInput calldata submission
    ) public view returns (bool) {
        // Hash the data according to EIP-712 standards
        bytes32 structHash = keccak256(
            abi.encode(
                SUBMIT_TYPEHASH,
                submission.dataHash,
                submission.da,
                keccak256(submission.cid)
            )
        );

        // Create the digest
        bytes32 digest = _hashTypedDataV4(structHash);

        // Verify the signature using SignatureChecker
        return SignatureChecker.isValidSignatureNow(submitter, digest, submission.signature);
    }

    function delegatedSubmit(
        address submitter,
        DelegatedSubmitInput calldata submission
    ) public {
        if (!verifySignature(submitter, submission)) {
            revert InvalidSignature();
        }

        _submit(submitter, submission.dataHash, submission.da, submission.cid);
    }

    function batchDelegatedSubmit(
        address submitter,
        DelegatedSubmitInput[] calldata submissions
    ) external {
        unchecked {
            uint256 len = submissions.length;
            for (uint256 i; i < len; ++i) {
                delegatedSubmit(submitter, submissions[i]);
            }
        }
    }

    function get(
        address submitter,
        bytes32 dataHash
    ) public view returns (DaCid[] memory result) {
        bytes32[] storage providers = dataProviders[submitter][dataHash];
        uint256 len = providers.length;

        if (len == 0) {
            // If no submission in the submitter, try finding old submissions in extended submitters
            address[] storage addresses = extendedAddresses[submitter];
            uint256 addressesLen = addresses.length;

            unchecked {
                for (uint256 i; i < addressesLen; ++i) {
                    result = get(addresses[addressesLen - i - 1], dataHash);
                    if (result.length > 0) return result;
                }
            }
        } else {
            result = new DaCid[](providers.length);

            unchecked {
                for (uint256 i; i < len; ++i) {
                    result[i] = DaCid({
                        da: providers[i],
                        cid: translation[submitter][dataHash][providers[i]]
                    });
                }
            }
        }
    }

    function extend(address old) external {
        extendedAddresses[msg.sender].push(old);
        emit Extend(msg.sender, old);
    }

    function getExtendedAddresses(
        address submitter
    ) public view returns (address[] memory) {
        return extendedAddresses[submitter];
    }
}
