enum SRPVectors {
    static let apple = (
        privateKey: String(repeating: "ab", count: 32),
        salt: String(repeating: "11", count: 16),
        derivedPassword: String(repeating: "cd", count: 32),
        username: "user@example.com",
        publicKey:
            "4b75ea6f77c9d1f4bb3ce7330d40aa499c61641b268c347f5ec67ad520cef230"
            + "7226c51262a9d86305ec02fb1072fb51a07e86eb31f5b50a23400e954c447cb96"
            + "0ed12d8557e15d66152be3591dc1be117ec718086efe3dec408894b903959e7bac"
            + "f0a598c2ab5255a4296318e873708567981e300eae0347cc650638ad73edee63c4"
            + "f0b4e0d14ad2bdaf16d808eae192d436ea56e9db832c6af5bbda38fe5d99f5a3"
            + "cee9fb1389af19fc0ed39bede553a70991e1835474ab5414ea9b7b6d48a719149"
            + "45feb0508d8dc31eb0d321d210b6ff90a4a5f16bf72e0a32a6d1e6de250f544b"
            + "84243bcccc9a576b09f9e6bb43d515636a9ccafcf800e0b92d1c530460",
        serverPublicKey:
            "8dd1ee4be3d294846d385a27656aba41c8b56bc4b890eb85d7de8f8ccff217cc"
            + "22a1a28050e0251886cde6db6cbb15ad6b39c0a5bea0c9163e8e6895f65c45ddc"
            + "db6dd992453b764b9f9ab7889738c6f0c869b4292c06c8e6cb6566a11879ec48f"
            + "9ec1c86d6c854feed0eecc88327f25fb33a9b36f3274930f60f62b18d83b78301"
            + "a2e62251dcc11f7c71927d1b3f849847adf32afd4d68af46ed550befe9ea561f5"
            + "84df6b2ff7fc04145f3178876ba7d6a1f1ec689185bd56ab2380f78d2ee8d84fd"
            + "360b19a32d10a642fdb57e1061b3da00e7ca3c78ce3fcd7ed79685c7d2390dac7"
            + "dfd8dd3933e716776d01e458819b3ece231c0ccc24d53155f756db3528",
        sharedSecret:
            "7fac108f02f4b23599c27aa235fa2bdc8590cf4428fb9f43a1cb0a3b2e98c055"
            + "7c13abded9ab9ecbd9442b1ef5f221226264e09bbcbe32ed21641c857f9cc83d70"
            + "5a27f53fea6d3939ff6a47f2cf7031fac6042199327678fac2e4d460e96aa20d3f"
            + "6edc42fb8e9979d93ce59e09dd35b3caa2bf263ae992e08c7efd16d28ba9488a4"
            + "3b68f27478b967852a0bb10346007afe391a6484bcb3d9c548aef777e2a3afcf1"
            + "b980d068bb95889004e856167b9d5a467d5c3c7cb659051b9db9e2d3ad7ad72b7"
            + "041739d4b2c50bbaacf5362244818203453411e7ad67c9eb3bcad0321a33873f28"
            + "d5c09d641eb99994710483ba1950521f1134ed533783d3f7d4b0d7a",
        sessionKey: "1077cbf83142d98fb18a20898765646ca525bb825f9449493a0de5aaf93272c4",
        clientProof: "dd07131d178799b05642682e55339544416f437be7b0e3afd21e64c3ce0d3464",
        serverProof: "238cc667b591dc26cc232f83dda0ae2e257402587031fb5ee67c311586880506"
    )

    static let leadingZeroServerPublicKey = (
        unpaddedServerPublicKey:
            "d1ee4be3d294846d385a27656aba41c8b56bc4b890eb85d7de8f8ccff217cc2"
            + "2a1a28050e0251886cde6db6cbb15ad6b39c0a5bea0c9163e8e6895f65c45ddcd"
            + "b6dd992453b764b9f9ab7889738c6f0c869b4292c06c8e6cb6566a11879ec48f9"
            + "ec1c86d6c854feed0eecc88327f25fb33a9b36f3274930f60f62b18d83b78301a"
            + "2e62251dcc11f7c71927d1b3f849847adf32afd4d68af46ed550befe9ea561f584"
            + "df6b2ff7fc04145f3178876ba7d6a1f1ec689185bd56ab2380f78d2ee8d84fd36"
            + "0b19a32d10a642fdb57e1061b3da00e7ca3c78ce3fcd7ed79685c7d2390dac7df"
            + "d8dd3933e716776d01e458819b3ece231c0ccc24d53155f756db3528",
        sharedSecret:
            "804074bc914d2d467b9f22ec82f28b88a718418cd068e7432d18df75789a7b63"
            + "b669ceef84e8cb3728a4ca6488aa4e5db36b3eb116e87052ca46678c991487df43"
            + "de8bf9878c95bded7b4b2f64ed1f56db4a358db5ae76f07231bcc0d0bbd0be18e"
            + "6b800742d09eb1a7eb866848f1ecca229d9951807600e6b712ae7710d4466bf020"
            + "c5bb120642df083c81b89092fa1bd0e367a9ef3839dd12445b9bbaaf63f13190a"
            + "3559ccbe26b31d0d869d80be1110068db238dd5746231da5c1201fce657a9eb6f"
            + "fbcb8c999488dc29d8918d0212c91774e9bb031b29d02b650280189504c5ccd263"
            + "4e7ba472306ec8af7d2d1d82647bf8d0adcdd82fa83a6fcd8b1831d",
        sessionKey: "8fd8e9f662e422e22bfee8bfd22869f819ff031a6e11032451cf0d8343f3ce7a",
        clientProof: "a5147be2fffc76098b99b54d2093df5dee275dba3f4c3bf5df0a2cfc8370cb91"
    )

    static let passwordDerivation = (
        password: "correct horse battery staple",
        salt: "00112233445566778899aabbccddeeff",
        iterations: 1_000,
        s2k: "27e4f98bda15ebc577083e895266e847a0ae9896bbc80cc07c3194a107ed34a6",
        s2kFO: "9601fa505b07f7552bbfa237464cb59ed582258b5672fbc1eb57bd36f284bd55"
    )
}
