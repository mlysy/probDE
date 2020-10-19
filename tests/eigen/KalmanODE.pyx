# cython: boundscheck=False, wraparound=False, nonecheck=False, initializedcheck=False
cimport cython
import numpy as np
cimport numpy as np

from probDE.utils import rand_mat
from KalmanTVODE cimport KalmanTVODE

DTYPE = np.double
ctypedef np.double_t DTYPE_t

cpdef kalman_ode(fun,
                 double[::1] x0_state,
                 double tmin,
                 double tmax,
                 int n_eval,
                 double[::1, :] wgt_state,
                 double[::1] mu_state, 
                 double[::1, :] var_state,
                 double[::1, :] wgt_meas, 
                 double[::1, :] z_state_sim,
                 object theta,
                 bint sim_sol = True):
    """
    Probabilistic ODE solver based on the Kalman filter and smoother. Returns an approximate solution to the higher order ODE

    .. math:: W x_n = F(x_n, n, \theta)

    on the time interval :math:`n \in [a, b]` with initial condition :math:`x_0 = x_0`. The corresponding variable names are

    The specific model we are using to approximate the solution :math:`x_n` is

    .. math::

        X_n = c + T X_{n-1} + R_n^{1/2} \epsilon_n

        y_n = d + W X_n + H_n^{1/2} \eta_n

    where :math:`\epsilon_n` and :math:`\eta_n` are independent :math:`N(0,1)` distributions and
    :math:`X_n = (x_n, y_n)` at time n and :math:`y_n` denotes the observation at time n.

    Args:
        fun (function): Higher order ODE function :math:`W x_n = F(x_n, n)` taking arguments :math:`x` and :math:`n`.
        x0_state (ndarray(n_state)): Initial value of the state variable :math:`x_n` at time :math:`n = 0`; :math:`x_0`.
        tmin (double): First time point of the time interval to be evaluated; :math:`a`.
        tmax (double): Last time point of the time interval to be evaluated; :math:`b`.
        n_eval (int): Number of discretization points (:math:`N`) of the time interval that is evaluated,
            such that discretization timestep is :math:`dt = (b-a)/N`.
        wgt_state (ndarray(n_state, n_state)): Transition matrix defining the solution prior; :math:`T`.
        mu_state (ndarray(n_state)): Transition_offsets defining the solution prior; :math:`c`.
        var_state (ndarray(n_state, n_state)): Variance matrix defining the solution prior; :math:`R`.
        wgt_meas (ndarray(n_meas, n_state)): Transition matrix defining the measure prior; :math:`W`.
        z_state_sim (ndarray(n_state, 2*n_steps)): Random N(0,1) matrix for forecasting and smoothing.
        theta (ndarray(n_theta)): Parameter in the ODE function.
        smooth_mv (bool): Flag for returning the smoothed mean and variance.
        smooth_sim (bool): Flag for returning the smoothed simulated state.

    Returns:
        (tuple):
        - **x_state_smooths** (ndarray(n_steps, n_state)): Sample solution at time t given observations from times [a...b].
        - **mu_state_smooths** (ndarray(n_steps, n_state)): Posterior mean of the solution process :math:`y_n` at times
          [a...b].
        - **var_state_smooths** (ndarray(n_steps, n_state, n_state)): Posterior variance of the solution process at
          times [a...b].

    """
    # Dimensions of state and measure variables
    cdef int n_meas = wgt_meas.shape[0]
    cdef int n_state = mu_state.shape[0]
    cdef int n_steps = n_eval + 1
    # argumgents for kalman_filter and kalman_smooth
    cdef np.ndarray[DTYPE_t, ndim=2] mu_state_smooths = np.zeros((n_state, n_steps),
                                                                 dtype=DTYPE, order='F')
    cdef np.ndarray[DTYPE_t, ndim=3] var_state_smooths = np.zeros((n_state, n_state, n_steps),
                                                                  dtype=DTYPE, order='F')
    cdef np.ndarray[DTYPE_t, ndim=2] x_state_smooths = np.zeros((n_state, n_steps),
                                                                dtype=DTYPE, order='F')
    
    cdef np.ndarray[DTYPE_t, ndim=1] x_state = np.zeros(n_state, dtype=DTYPE, order='F')
    cdef np.ndarray[DTYPE_t, ndim=2] x_meas = np.zeros((n_meas, n_steps), dtype=DTYPE, order='F')

    cdef int t
    # forward pass
    ktvode = new KalmanTVODE(n_meas, n_state, n_steps, & x0_state[0],
                             & x_state[0], & mu_state[0], & wgt_state[0, 0],
                             & var_state[0, 0], & x_meas[0, 0], & wgt_meas[0, 0], 
                             & z_state_sim[0, 0], & x_state_smooths[0, 0],
                             & mu_state_smooths[0, 0], & var_state_smooths[0, 0, 0])

    for t in range(n_eval):
        # kalman filter:
        ktvode.predict(t)
        ktvode.forecast(t)
        #ktvode.forecast_sch(t)
        fun(x_state, tmin + (tmax-tmin)*(t+1)/n_eval, theta, x_meas[:, t+1])
        ktvode.update(t)
       
    # backward pass
    ktvode.smooth_update(sim_sol)
    del ktvode
    if sim_sol:
        return x_state_smooths
    else:
        return mu_state_smooths, var_state_smooths
    
cpdef _copynm(dest, source, name):
    if not source.data.f_contiguous:
        raise TypeError('{} is not f contiguous.'.format(name))
    if not source.shape==dest.shape:
        raise TypeError('{} has incorrect shape.'.format(name))
    dest[:] = source
    return source

cdef class KalmanODE:
    """
    Create an object with the method of a probabilistic ODE solver, :func:`kalman_ode`, based on the Kalman filter and smoother. 

    Args:
        n_state (int): Size of the state.
        n_meas (int): Size of the measure.
        tmin (double): First time point of the time interval to be evaluated; :math:`a`.
        tmax (double): Last time point of the time interval to be evaluated; :math:`b`.
        n_eval (int): Number of discretization points (:math:`N`) of the time interval that is evaluated,
            such that discretization timestep is :math:`dt = b/N`.
        fun (function): Higher order ODE function :math:`W x_n = F(x_n, n)` taking arguments :math:`x` and :math:`n`.
        wgt_state (ndarray(n_state, n_state)): Transition matrix defining the solution prior; :math:`T`.
        mu_state (ndarray(n_state)): Transition_offsets defining the solution prior; :math:`c`.
        var_state (ndarray(n_state, n_state)): Variance matrix defining the solution prior; :math:`R`.
        z_states (ndarray(n_state)): Random matrix for simulating from :math:`N(0, 1)`.

    """
    cdef int n_state, n_meas, n_eval, n_steps
    cdef double tmin, tmax
    cdef object fun
    cdef double[::1, :] __wgt_state
    cdef double[::1] __mu_state
    cdef double[::1, :] __var_state
    cdef double[::1, :] __z_states
        
    def __cinit__(self, int n_state, int n_meas, double tmin, double tmax, int n_eval, object fun, **init):
        self.n_state = n_state
        self.n_meas = n_meas
        self.tmin = tmin
        self.tmax = tmax
        self.n_eval = n_eval
        self.n_steps = n_eval + 1
        self.fun = fun
        self.__wgt_state = np.empty((self.n_state, self.n_state), order='F')
        self.__mu_state = np.empty(self.n_state, order='F')
        self.__var_state = np.empty((self.n_state, self.n_state), order='F')
        self.__z_states = np.empty((self.n_state, 2*self.n_steps), order='F')
        for key in init.keys():
            self.__setattr__(key, init[key])
    
    @property
    def mu_state(self):
        return self.__mu_state

    @mu_state.setter
    def mu_state(self, mu_state):
        _copynm(self.__mu_state, mu_state, 'mu_state')
    
    @mu_state.deleter
    def mu_state(self):
        self.__mu_state = None

    @property
    def var_state(self):
        return self.__var_state

    @var_state.setter
    def var_state(self, var_state):
        _copynm(self.__var_state, var_state, 'var_state')
    
    @var_state.deleter
    def var_state(self):
        self.__var_state = None

    @property
    def wgt_state(self):
        return self.__wgt_state

    @wgt_state.setter
    def wgt_state(self, wgt_state):
        _copynm(self.__wgt_state, wgt_state, 'wgt_state')
    
    @wgt_state.deleter
    def wgt_state(self):
        self.__wgt_state = None

    @property
    def z_states(self):
        return self.__z_states

    @z_states.setter
    def z_states(self, z_states):
        _copynm(self.__z_states, z_states, 'z_states')
    
    @z_states.deleter
    def z_states(self):
        self.__z_states = None

    cpdef solve(self, double[::1] x0_state, double[::1, :] wgt_meas, object theta=None, bint sim_sol=True):
        r"""
        Returns an approximate solution to the higher order ODE

        .. math:: W x_n = F(x_n, t, \theta)

        on the time interval :math:`t \in [a, b]` with initial condition :math:`x_0 = x_0`.
        
        Args:
            x0_state (ndarray(n_state)): Initial value of the state variable :math:`x_n` at time :math:`t = 0`; :math:`x_0`.
            wgt_meas (ndarray(n_var, n_state)): Transition matrix defining the measure prior; :math:`W`.
            theta (ndarray(n_theta)): Parameter in the ODE function.
            smooth_mv (bool): Flag for returning the smoothed mean and variance.
            smooth_sim (bool): Flag for returning the smoothed simulated state.
        
        Returns:
            (tuple):
            - **kalman_sim** (ndarray(n_steps, n_state)): Sample solution at time t given observations from times [a...b].
            - **kalman_mu** (ndarray(n_steps, n_state)): Posterior mean of the solution process :math:`y_n` at times
              [a...b].
            - **kalman_var** (ndarray(n_steps, n_state, n_state)): Posterior variance of the solution process at
              times [a...b].

        """
        if (self.__wgt_state is None or self.__mu_state is None or 
           self.__var_state is None):
            raise ValueError("wgt_state, mu_state, and/or var_state is not set.")
        
        if self.__z_states is None:
            self.__z_states = rand_mat(2*(self.n_eval+1), self.n_state)
        
        if not np.asarray(x0_state).data.f_contiguous:
            raise TypeError('{} is not f contiguous.'.format('x0_state'))
        if len(x0_state)!=self.n_state:
            raise TypeError('{} has incorrect shape.'.format('x0_state'))
        
        if not np.asarray(wgt_meas).data.f_contiguous:
            raise TypeError('{} is not f contiguous.'.format('wgt_meas'))
        if np.asarray(wgt_meas).shape!=(self.n_meas, self.n_state):
            raise TypeError('{} has incorrect shape.'.format('wgt_meas'))

        out = kalman_ode(self.fun, x0_state, self.tmin, self.tmax, self.n_eval,
                         self.__wgt_state, self.__mu_state, self.__var_state,
                         wgt_meas, self.__z_states, theta, sim_sol)
        if sim_sol:
            kalman_sim = np.ascontiguousarray(out.T)
            return kalman_sim
        else:
            kalman_mu = np.ascontiguousarray(out[0].T)
            kalman_var = np.ascontiguousarray(out[1].T)
            return kalman_mu, kalman_var
        