"""
.. module:: var_car

Covariance function for the CAR(p) process:

.. math:: cov(X_0, X_t)

"""

import numpy as np
import BayesODE.Kalman._mou_car as mc

def cov_car(tseq, roots, sigma=1., corr=False, v_infinity=False):
    """Computes the covariance function for the CAR(p) process :math: `cov(X_0, X_t)`
    
    Parameters
    ----------
    
    tseq: [N] :obj:`numpy.ndarray` of float
        Time points at which :math: `x_t` is evaluated. 
    roots: [p] :obj:`numpy.ndarray` of float
        Roots to the p-th order polynomial of the car(p) process (roots must be negative)
    sigma: float
        Parameter in mOU volatility matrix
    
    Returns
    -------
    
    C: [N, p, p]  numpy.ndarray
        Evaluates :math:`cov(X_0, X_t)` or :math:`corr(X_0, X_t)` or :math:`V_{\infty}`.
    """
    p = len(roots)
    delta = np.array(-roots)
    Sigma_tilde, Q = mc._mou_car(roots, sigma)

    Q_inv = np.linalg.pinv(Q)
    # V_tilde_inf
    V_tilde_inf = np.zeros((p, p))
    for i in range(p):
        for j in range(i, p):
            V_tilde_inf[i, j] = Sigma_tilde[i, j] / \
                (delta[i] + delta[j])
            V_tilde_inf[j, i] = V_tilde_inf[i, j]
    
    V_inf = np.linalg.multi_dot([Q, V_tilde_inf, Q.T])
    if corr:
        sd_inf = np.sqrt(np.diag(V_inf))  # stationary standard deviations
    if v_infinity:
        return V_inf

    # covariance matrix
    C = np.zeros((len(tseq), p, p))
    for t in range(len(tseq)):
        # V = np.linalg.multi_dot([Q, V_tilde_inf, Q.T])  # Q*V_tilde_inf*Q.T
        # exp(-Gamma*t) = Q*exp(-D*t)*Q^-1
        exp_Gamma_t = np.matmul(Q_inv.T * np.exp(-delta * tseq[t]), Q.T)
        C[t] = V_inf.dot(exp_Gamma_t)
        if corr:
            C[t] = (C[t] / sd_inf).T
            C[t] = (C[t] / sd_inf).T
    return C