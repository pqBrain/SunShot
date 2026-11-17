@testable import SunshotCore

/// One recognisable sample per starter language (used by highlighter and detection tests).
enum CodeFixtures {
    static let samples: [CodeLanguage: String] = [
        .swift: CodeSnippet.starterCode,
        .javascript: """
        // Fetch the forecast
        const city = "Lisbon";
        function forecast(days) {
          return fetch(`/api/${city}?days=${days}`).then((r) => r.json());
        }
        console.log(forecast(3) === undefined);
        """,
        .typescript: """
        interface Sunrise { hour: number; label: string }
        export type Mode = "light" | "dark";
        const first: Sunrise = { hour: 6, label: "dawn" };
        function shift(value: number): number { return value + 1 }
        """,
        .python: """
        # Count sunny days
        def sunny_days(readings):
            total = 0
            for value in readings:
                if value > 0.5:
                    total += 1
            return total

        print(sunny_days([0.2, 0.9, 0.7]))
        """,
        .json: """
        {
          "name": "Sunshot",
          "version": 2,
          "light": true,
          "tags": ["code", null]
        }
        """,
        .markup: """
        <!-- Greeting -->
        <div class="card" id='hero'>
          <p>Hello &amp; welcome</p>
          <img src="sun.png" />
        </div>
        """,
        .css: """
        /* Card */
        .card {
          color: #1d4ed8;
          margin: 12px 0;
          display: flex;
        }
        @media (max-width: 600px) {
          .card { padding: 8px; }
        }
        """,
        .shell: """
        #!/bin/bash
        # Build and copy
        name="sunshot"
        if [ -d build ]; then
          echo "Copying ${name}"
          cp -r build $HOME/dist
        fi
        """,
        .go: """
        package main

        import "fmt"

        // Greet says hello
        func main() {
        \thour := 6
        \tfmt.Println("Good morning", hour)
        }
        """,
        .rust: """
        // A sunrise
        #[derive(Debug)]
        struct Sunrise<'a> { label: &'a str }

        fn main() {
            let mut hour: u32 = 6;
            println!("Good morning {}", hour);
        }
        """,
        .sql: """
        -- Sunny cities
        SELECT name, COUNT(*) AS days
        FROM readings
        WHERE light > 0.5
        GROUP BY name
        ORDER BY days DESC;
        """,
        .plainText: "Remember to water the plants on Tuesday.\nThen call Sam.",
    ]

    static func sample(_ language: CodeLanguage) -> String { samples[language] ?? "" }
}
