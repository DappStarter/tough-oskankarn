import NonFungibleToken from Flow.NonFungibleToken


pub contract DappState
                    : NonFungibleToken // for additional interfaces, separate with a comma

{

    pub var totalSupply: UInt64

    pub event ContractInitialized()
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)

    pub resource NFT: NonFungibleToken.INFT {
        pub let id: UInt64

        pub var metadata: {String: String}

        init(initID: UInt64) {
            self.id = initID
            self.metadata = {}
        }
    }

    pub resource Collection: NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic {
        // dictionary of NFT conforming tokens
        // NFT is a resource type with an `UInt64` ID field
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        init () {
            self.ownedNFTs <- {}
        }

        // withdraw removes an NFT from the collection and moves it to the caller
        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            let token <- self.ownedNFTs.remove(key: withdrawID) ?? panic("missing NFT")

            emit Withdraw(id: token.id, from: self.owner?.address)

            return <-token
        }

        // deposit takes a NFT and adds it to the collections dictionary
        // and adds the ID to the id array
        pub fun deposit(token: @NonFungibleToken.NFT) {
            let token <- token as! @DappState.NFT

            let id: UInt64 = token.id

            // add the new token to the dictionary which removes the old one
            let oldToken <- self.ownedNFTs[id] <- token

            emit Deposit(id: id, to: self.owner?.address)

            destroy oldToken
        }

        // getIDs returns an array of the IDs that are in the collection
        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        // borrowNFT gets a reference to an NFT in the collection
        // so that the caller can read its metadata and call its methods
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT
        }

        destroy() {
            destroy self.ownedNFTs
        }
    }

    // public function that anyone can call to create a new empty collection
    pub fun createEmptyCollection(): @NonFungibleToken.Collection {
        return <- create Collection()
    }

    // Resource that an admin or something similar would own to be
    // able to mint new NFTs
    //
    pub resource NFTMinter {

        // mintNFT mints a new NFT with a new ID
        // and deposit it in the recipients collection using their collection reference
        pub fun mintNFT(recipient: &{NonFungibleToken.CollectionPublic}) {

            // create a new NFT
            var newNFT <- create NFT(initID: DappState.totalSupply)

            // deposit it in the recipient's account using their reference
            recipient.deposit(token: <-newNFT)

            DappState.totalSupply = DappState.totalSupply + UInt64(1)
        }
    }

    //list of proposals to be approved
    pub var proposals: [String]

    // number of votes per proposal
    pub let votes: {Int: Int}

    // This is the resource that is issued to users.
    // When a user gets a Ballot object, they call the `vote` function
    // to include their votes, and then cast it in the smart contract 
    // using the `cast` function to have their vote included in the polling
    pub resource Ballot {

        // array of all the proposals 
        pub let proposals: [String]

        // corresponds to an array index in proposals after a vote
        pub var choices: {Int: Bool}

        init() {
            self.proposals = DappState.proposals
            self.choices = {}
            
            // Set each choice to false
            var i = 0
            while i < self.proposals.length {
                self.choices[i] = false
                i = i + 1
            }
        }

        // modifies the ballot
        // to indicate which proposals it is voting for
        pub fun vote(proposal: Int) {
            pre {
                self.proposals[proposal] != nil: "Cannot vote for a proposal that doesn't exist"
            }
            self.choices[proposal] = true
        }
    }

    // Resource that the Administrator of the vote controls to
    // initialize the proposals and to pass out ballot resources to voters
    pub resource Administrator {

        // function to initialize all the proposals for the voting
        pub fun initializeProposals(_ proposals: [String]) {
            pre {
                DappState.proposals.length == 0: "Proposals can only be initialized once"
                proposals.length > 0: "Cannot initialize with no proposals"
            }
            DappState.proposals = proposals

            // Set each tally of votes to zero
            var i = 0
            while i < proposals.length {
                DappState.votes[i] = 0
                i = i + 1
            }
        }

        // The admin calls this function to create a new Ballot
        // that can be transferred to another user
        pub fun issueBallot(): @Ballot {
            return <-create Ballot()
        }
    }

    // A user moves their ballot to this function in the contract where 
    // its votes are tallied and the ballot is destroyed
    pub fun cast(ballot: @Ballot) {
        var index = 0
        // look through the ballot
        while index < self.proposals.length {
            if ballot.choices[index]! {
                // tally the vote if it is approved
                self.votes[index] = self.votes[index]! + 1
            }
            index = index + 1
        }
        // Destroy the ballot because it has been tallied
        destroy ballot
    }

    pub fun proposalList(): [String] {
        return self.proposals
    }



    init() {

    // Initialize the total supply
    self.totalSupply = 0

    // Create a Collection resource and save it to storage
    let collection <- create Collection()
    self.account.save(<-collection, to: /storage/NFTCollection)

    // create a public capability for the collection
    self.account.link<&{NonFungibleToken.CollectionPublic}>(
        /public/NFTCollection,
        target: /storage/NFTCollection
    )

    // Create a Minter resource and save it to storage
    let minter <- create NFTMinter()
    self.account.save(<-minter, to: /storage/NFTMinter)

    emit ContractInitialized()

    // initializes the contract by setting the proposals and votes to empty 
    // and creating a new Admin resource to put in storage
    self.proposals = []
    self.votes = {}
    self.account.save(<-create Administrator(), to: /storage/VotingAdmin)



    }
}