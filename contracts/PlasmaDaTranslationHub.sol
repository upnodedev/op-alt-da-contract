// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/**
 * @title PlasmaDaTranslationHub
 * @notice This contract manages the submission and verification of translation data using the Plasma Data Availability (DA) model.
 * @dev Implements EIP-712 for signature verification and utilizes SignatureChecker for secure submission delegation.
 */
contract PlasmaDaTranslationHub is EIP712 {
    /// @notice Error thrown when a signature is invalid.
    error InvalidSignature();

    /// @notice Error thrown when a submission is duplicated.
    error DuplicatedSubmission();

    /// @notice Mapping of submitter, data hash, DA ID to CID of that DA
    mapping(address => mapping(bytes32 => mapping(bytes32 => bytes))) translation;
    
    /// @notice Mapping of submitter and data hash to DA IDs that provide the data availability
    mapping(address => mapping(bytes32 => bytes32[])) daProviders;

    /// @notice Extended or old addresses for each submitter
    mapping(address => address[]) extendedAddresses;

    /**
     * @notice Event emitted when a translation is successfully submitted.
     * @param submitter The address of the submitter.
     * @param dataHash The hash of the data being submitted.
     * @param da The Data Availability (DA) identifier.
     * @param cid The content identifier (CID) associated with the submission.
     */
    event TranslationSubmitted(
        address indexed submitter,
        bytes32 indexed dataHash,
        bytes32 indexed da,
        bytes cid
    );

    /**
     * @notice Event emitted when a submitter is extended to include another address.
     * @param newSubmitter The new submitter's address.
     * @param oldSubmitter The old submitter's address.
     */
    event Extend(address indexed newSubmitter, address indexed oldSubmitter);

    /**
     * @notice Struct representing the DA and CID associated with a submission.
     */
    struct DaCid {
        bytes32 da;
        bytes cid;
    }

    /**
     * @notice Struct representing the input for a batch submission.
     */
    struct BatchSubmitInput {
        bytes32 dataHash;
        bytes32 da;
        bytes cid;
    }

    /**
     * @notice Struct representing the input for a delegated submission.
     */
    struct DelegatedSubmitInput {
        bytes32 dataHash;
        bytes32 da;
        bytes cid;
        bytes signature;
    }

    /// @notice The type hash used for EIP-712 signature verification
    bytes32 private constant SUBMIT_TYPEHASH =
        keccak256("PlasmaDaSubmit(bytes32 dataHash,bytes32 da,bytes cid)");

    /**
     * @notice Constructor initializing the PlasmaDaTranslationHub with EIP-712 domain separator.
     */
    constructor() EIP712("PlasmaDaTranslationHub", "1") {}

    /**
     * @notice Internal function to handle the submission of translation data.
     * @param submitter The address of the submitter.
     * @param dataHash The hash of the data being submitted.
     * @param da The Data Availability (DA) identifier.
     * @param cid The content identifier (CID) associated with the submission.
     * @dev Reverts if the data has already been submitted by the submitter for the given dataHash and DA.
     */
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
        daProviders[submitter][dataHash].push(da);

        emit TranslationSubmitted(submitter, dataHash, da, cid);
    }

    /**
     * @notice Submits translation data (msg.sender, dataHash, da) -> cid
     * @param dataHash The hash of the data being submitted.
     * @param da The Data Availability (DA) identifier.
     * @param cid The content identifier (CID) associated with the submission.
     */
    function submit(bytes32 dataHash, bytes32 da, bytes calldata cid) external {
        _submit(msg.sender, dataHash, da, cid);
    }

    /**
     * @notice Submits multiple translation data entries in a batch.
     * @param submissions An array of BatchSubmitInput containing the dataHash, DA, and CID for each submission.
     */
    function batchSubmit(BatchSubmitInput[] calldata submissions) external {
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

    /**
     * @notice Verifies the signature of a delegated submission.
     * @param submitter The address of the submitter.
     * @param submission The DelegatedSubmitInput containing the dataHash, DA, CID, and signature.
     * @return bool Returns true if the signature is valid, otherwise false.
     */
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
        return
            SignatureChecker.isValidSignatureNow(
                submitter,
                digest,
                submission.signature
            );
    }

    /**
     * @notice Submits translation data on behalf of another address, verified via signature.
     * @param submitter The address of the submitter.
     * @param submission The DelegatedSubmitInput containing the dataHash, DA, CID, and signature.
     * @dev Reverts if the signature is invalid.
     */
    function delegatedSubmit(
        address submitter,
        DelegatedSubmitInput calldata submission
    ) public {
        if (!verifySignature(submitter, submission)) {
            revert InvalidSignature();
        }

        _submit(submitter, submission.dataHash, submission.da, submission.cid);
    }

    /**
     * @notice Submits multiple translation data entries in a batch on behalf of another address, verified via signatures.
     * @param submitter The address of the submitter.
     * @param submissions An array of DelegatedSubmitInput containing the dataHash, DA, CID, and signature for each submission.
     * @dev Reverts if a signature is invalid.
     */
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

    /**
     * @notice Retrieves all DA and CID associated with a submitter and dataHash.
     * @param submitter The address of the submitter.
     * @param dataHash The hash of the data being queried.
     * @return result An array of DaCid structs containing the DA and CID for each submission.
     */
    function getAll(
        address submitter,
        bytes32 dataHash
    ) public view returns (DaCid[] memory result) {
        bytes32[] storage providers = daProviders[submitter][dataHash];
        uint256 len = providers.length;

        if (len == 0) {
            // If no submission in the submitter, try finding old submissions in extended submitters
            address[] storage addresses = extendedAddresses[submitter];
            uint256 addressesLen = addresses.length;

            unchecked {
                for (uint256 i; i < addressesLen; ++i) {
                    result = getAll(addresses[addressesLen - i - 1], dataHash);
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

    /**
     * @notice Retrieves translation data associated with a submitter, dataHash, and DA.
     * @param submitter The address of the submitter.
     * @param dataHash The hash of the data being queried.
     * @param da The Data Availability (DA) identifier.
     * @return cid The content identifier (CID) associated with the submission.
     */
    function get(
        address submitter,
        bytes32 dataHash,
        bytes32 da
    ) public view returns (bytes memory cid) {
        cid = translation[submitter][dataHash][da];

        if (cid.length == 0) {
            // If no submission in the submitter, try finding an old submission in extended submitters
            address[] storage addresses = extendedAddresses[submitter];
            uint256 addressesLen = addresses.length;

            unchecked {
                for (uint256 i; i < addressesLen; ++i) {
                    cid = get(addresses[addressesLen - i - 1], dataHash, da);
                    if (cid.length > 0) return cid;
                }
            }
        }
    }

    /**
     * @notice Extends the submitter's address to include another address.
     * @param old The address to be included as an extension of the submitter.
     * @dev Allows a submitter to inherit submissions made by the extended address.
     */
    function extend(address old) external {
        extendedAddresses[msg.sender].push(old);
        emit Extend(msg.sender, old);
    }

    /**
     * @notice Retrieves all extended addresses associated with a submitter.
     * @param submitter The address of the submitter.
     * @return An array of addresses that are extended to the submitter.
     */
    function getExtendedAddresses(
        address submitter
    ) public view returns (address[] memory) {
        return extendedAddresses[submitter];
    }
}
