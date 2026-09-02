"use client";

import { useState } from "react";

export default function Home() {
  const [entered, setEntered] = useState(false);
  const [email, setEmail] = useState("");
  const [joined, setJoined] = useState(false);

  function joinWaitlist(e) {
    e.preventDefault();

    if (!email.trim()) return;

    setJoined(true);
  }

  return (
    <main className={`site ${entered ? "entered" : ""}`}>

      <header>
        <div className="logo">
          LAYER X
        </div>

        <button
          className="menu"
          onClick={() => setEntered(true)}
          aria-label="Enter Layer X"
        >
          <span />
          <span />
        </button>
      </header>

      <div className="doorArea">
        <img
          src="/door.png"
          alt=""
          className="door"
        />
      </div>

      <section className="content">

        {!entered ? (
          <>
            <p className="tagline">
              THE WORLD ISN&apos;T EMPTY.
              <br />
              YOU&apos;RE JUST NOT SEEING IT YET.
            </p>

            <button
              className="enterButton"
              onClick={() => setEntered(true)}
            >
              ENTER <span>→</span>
            </button>
          </>
        ) : (
          <div className="reveal">

            <p className="small">
              SOMETHING IS ALREADY HERE.
            </p>

            <h1>
              JOIN THE
              <br />
              FIRST LAYER.
            </h1>

            {!joined ? (
              <form onSubmit={joinWaitlist}>

                <label>
                  EARLY ACCESS
                </label>

                <div className="email">

                  <input
                    type="email"
                    placeholder="YOUR EMAIL"
                    value={email}
                    onChange={(e) =>
                      setEmail(e.target.value)
                    }
                    required
                  />

                  <button type="submit">
                    →
                  </button>

                </div>

              </form>
            ) : (
              <p className="joined">
                YOU&apos;RE IN. WATCH THIS SPACE.
              </p>
            )}

          </div>
        )}

      </section>

      <footer>
        © LAYER X 2026
      </footer>

    </main>
  );
}
