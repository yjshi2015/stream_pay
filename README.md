# stream_pay

# mainnet packageId : 0xa769a20c9b8e80078bdad52ce1a2ecc4fb0d7c8df815e3b089bb6893913042e5
# Digest: HvdkDmgjy8jdiXosTH9etjUwrvmE7fXrdC66bntVk1ZA


## call createPayPoolAndStream 
sui client call --function createPayPoolAndStream --package 0xa60804309db3c87d785ecee5fcdab72aacc13aa567275e2b4d54f5bbf15f525d --module liner_pay --args 0x1dd33236e70b8cb34f8099a94dab2a70b286848bafd8cfcecea6010b01c0f1b6 "[0x961d00737596a517b1b1e519b47bf0bf100c51fcb40427f197d14268ebd5a6ee]" "[1]" 0x6


## call createAndDeposit  alice
sui client call --function createAndDeposit --package 0x29379cc662cd00266b9bb87db9cadfdafd1bd5215bc4b3dc9779653a66e01a0e --module liner_pay --args 0x834ed47a1d853f122dbba3913ae0c37ebeff08b3f0b4396943d5194bcc51ff44

Transaction Digest: G5EwZLahMasHyab7xjk9NU6Lu6viSBEkVDEV1hQPULYP

## call createStream of bob (1 MST/s)
sui client call --function createStream --package 0x8096b927f041dbcb156aa0dfa8e6804fe8c9383d9ed15dee5fae5c2d70cd7dd7 --module liner_pay --args 0x9daf7082b8d6d8f7ad48e29e334ce82b86ff4fc1ce52f00562680dca7790d21f 0xc4301a727914c051c987331f30d002ef907f6f6e4badfec8981e6275ed22486c 1 0x6

Transaction Digest: 42oK87UDupFFQD9hn51WvvsSmYYvRHePscxkG2mf3bMe

sui client call --function createStream --package 0x8096b927f041dbcb156aa0dfa8e6804fe8c9383d9ed15dee5fae5c2d70cd7dd7 --module liner_pay --args 0x9daf7082b8d6d8f7ad48e29e334ce82b86ff4fc1ce52f00562680dca7790d21f 0x9ebe2a46d2ec46eb9990d3a03a3241398e648c39bf157956b711640e717110d6 2 0x6

Transaction Digest: EY6yRwQdoxAShxL5kgtLeu5tB1rcyQMPA8drwhHs69s

## call withdraw of bob
sui client switch --address xxxx

sui client call --function withdraw --package 0x8096b927f041dbcb156aa0dfa8e6804fe8c9383d9ed15dee5fae5c2d70cd7dd7 --module liner_pay --args 0x9daf7082b8d6d8f7ad48e29e334ce82b86ff4fc1ce52f00562680dca7790d21f 0x855f1470ad46e3b56abd2b8e554ed808408a8c40c1ba397b340972e635bc617d 1 0x6

Transaction Digest: C8nGxEyvB5aPLp7XQJL9eWxr3osJz6gowPwnjKqTLdL6

## call getPayerBalance
sui client call --function getPayerBalance --package 0x9eb2648c160c70854b39d1b1d9e828b0f918efe2daf798d9fd936b9d075bc5e1 --module liner_pay --args 0x8dbfeb48a0f8c0d55ef6daf75e08b2f3a54ce3d294812bad49f7987bf7e8485d 0x6

### not ok
sui client ptb --move-call 0x9eb2648c160c70854b39d1b1d9e828b0f918efe2daf798d9fd936b9d075bc5e1::liner_pay::getPayerBalance @0x8dbfeb48a0f8c0d55ef6daf75e08b2f3a54ce3d294812bad49f7987bf7e8485d @0x6 --assign bal


## call withdrawPayerAll
sui client call --function withdrawPayerAll --package 0x9eb2648c160c70854b39d1b1d9e828b0f918efe2daf798d9fd936b9d075bc5e1 --module liner_pay --args 0x8dbfeb48a0f8c0d55ef6daf75e08b2f3a54ce3d294812bad49f7987bf7e8485d 0x6

## call withdrawPayer
sui client call --function withdrawPayer --package 0x8096b927f041dbcb156aa0dfa8e6804fe8c9383d9ed15dee5fae5c2d70cd7dd7 --module liner_pay --args 0x9daf7082b8d6d8f7ad48e29e334ce82b86ff4fc1ce52f00562680dca7790d21f 1 0x6

Transaction Digest: 8X7izLNugXkcqo531UafStwi872psu8vi9tzY4LtaD8x
